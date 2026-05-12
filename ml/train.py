from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import torch
from torch import nn
from torch.utils.data import DataLoader

from dataset import (
    LABELS,
    BellDecisionDataset,
    build_tag_vocab,
    load_annotations,
    split_by_photo_id,
    validate_crops,
)
from model import BellDecisionModel


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset-dir", type=Path, default=Path("Example photos/dataset"))
    parser.add_argument("--artifacts-dir", type=Path, default=Path("ml/artifacts"))
    parser.add_argument("--epochs", type=int, default=40)
    parser.add_argument("--batch-size", type=int, default=8)
    parser.add_argument("--image-size", type=int, default=224)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--weight-decay", type=float, default=1e-4)
    parser.add_argument("--val-ratio", type=float, default=0.2)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--pretrained", action="store_true")
    parser.add_argument("--unfreeze-backbone", action="store_true")
    return parser.parse_args()


def compute_metrics(predictions: list[int], labels: list[int], num_classes: int) -> dict[str, object]:
    matrix = np.zeros((num_classes, num_classes), dtype=np.int64)
    for target, prediction in zip(labels, predictions):
        matrix[target, prediction] += 1

    f1_scores: list[float] = []
    for class_id in range(num_classes):
        tp = matrix[class_id, class_id]
        fp = matrix[:, class_id].sum() - tp
        fn = matrix[class_id, :].sum() - tp
        precision = tp / (tp + fp) if tp + fp > 0 else 0.0
        recall = tp / (tp + fn) if tp + fn > 0 else 0.0
        f1 = 2 * precision * recall / (precision + recall) if precision + recall > 0 else 0.0
        f1_scores.append(float(f1))

    accuracy = float(np.trace(matrix) / matrix.sum()) if matrix.sum() else 0.0
    return {
        "accuracy": accuracy,
        "macro_f1": float(np.mean(f1_scores)),
        "per_class_f1": f1_scores,
        "confusion_matrix": matrix.tolist(),
    }


def evaluate(
    model: BellDecisionModel,
    loader: DataLoader,
    criterion: nn.Module,
    device: torch.device,
) -> tuple[float, dict[str, object]]:
    model.eval()
    total_loss = 0.0
    predictions: list[int] = []
    labels: list[int] = []
    with torch.no_grad():
        for image, tag_one_hot, confidence, label in loader:
            image = image.to(device)
            tag_one_hot = tag_one_hot.to(device)
            confidence = confidence.to(device)
            label = label.to(device)
            logits = model(image, tag_one_hot, confidence)
            loss = criterion(logits, label)
            total_loss += float(loss.item()) * label.size(0)
            predictions.extend(torch.argmax(logits, dim=1).cpu().tolist())
            labels.extend(label.cpu().tolist())

    metrics = compute_metrics(predictions, labels, len(LABELS))
    return total_loss / max(1, len(labels)), metrics


def main() -> None:
    args = parse_args()
    torch.manual_seed(args.seed)
    np.random.seed(args.seed)

    rows = load_annotations(args.dataset_dir)
    validate_crops(args.dataset_dir, rows)
    train_rows, val_rows = split_by_photo_id(rows, args.val_ratio, args.seed)
    tag_vocab = build_tag_vocab(train_rows)
    label_map = {label: index for index, label in enumerate(LABELS)}

    train_dataset = BellDecisionDataset(
        args.dataset_dir, train_rows, tag_vocab, label_map, args.image_size, train=True
    )
    val_dataset = BellDecisionDataset(
        args.dataset_dir, val_rows, tag_vocab, label_map, args.image_size, train=False
    )
    train_loader = DataLoader(train_dataset, batch_size=args.batch_size, shuffle=True)
    val_loader = DataLoader(val_dataset, batch_size=args.batch_size, shuffle=False)

    device = torch.device("cuda" if torch.cuda.is_available() else "mps" if torch.backends.mps.is_available() else "cpu")
    model = BellDecisionModel(
        tag_vocab_size=len(tag_vocab),
        num_classes=len(LABELS),
        pretrained=args.pretrained,
        freeze_backbone=not args.unfreeze_backbone,
    ).to(device)

    class_counts = torch.bincount(
        torch.tensor([label_map[row.decision] for row in train_rows]),
        minlength=len(LABELS),
    ).float()
    class_weights = class_counts.sum() / class_counts.clamp_min(1.0)
    criterion = nn.CrossEntropyLoss(weight=class_weights.to(device))
    optimizer = torch.optim.AdamW(
        [parameter for parameter in model.parameters() if parameter.requires_grad],
        lr=args.lr,
        weight_decay=args.weight_decay,
    )

    best_macro_f1 = -1.0
    best_payload: dict[str, object] | None = None
    args.artifacts_dir.mkdir(parents=True, exist_ok=True)

    for epoch in range(1, args.epochs + 1):
        model.train()
        total_loss = 0.0
        seen = 0
        for image, tag_one_hot, confidence, label in train_loader:
            image = image.to(device)
            tag_one_hot = tag_one_hot.to(device)
            confidence = confidence.to(device)
            label = label.to(device)

            optimizer.zero_grad(set_to_none=True)
            logits = model(image, tag_one_hot, confidence)
            loss = criterion(logits, label)
            loss.backward()
            optimizer.step()

            total_loss += float(loss.item()) * label.size(0)
            seen += label.size(0)

        val_loss, val_metrics = evaluate(model, val_loader, criterion, device)
        train_loss = total_loss / max(1, seen)
        print(
            f"epoch={epoch:03d} train_loss={train_loss:.4f} "
            f"val_loss={val_loss:.4f} val_macro_f1={val_metrics['macro_f1']:.4f} "
            f"val_acc={val_metrics['accuracy']:.4f}",
            flush=True,
        )
        if float(val_metrics["macro_f1"]) > best_macro_f1:
            best_macro_f1 = float(val_metrics["macro_f1"])
            best_payload = {
                "model_state": model.state_dict(),
                "tag_vocab": tag_vocab,
                "label_map": label_map,
                "image_size": args.image_size,
                "metrics": val_metrics,
                "config": {
                    "pretrained": args.pretrained,
                    "freeze_backbone": not args.unfreeze_backbone,
                },
            }

    if best_payload is None:
        raise RuntimeError("Training produced no checkpoint")

    checkpoint_path = args.artifacts_dir / "bell_classifier.pt"
    torch.save(best_payload, checkpoint_path)
    (args.artifacts_dir / "tag_vocab.json").write_text(
        json.dumps(best_payload["tag_vocab"], indent=2, sort_keys=True),
        encoding="utf-8",
    )
    (args.artifacts_dir / "label_map.json").write_text(
        json.dumps(best_payload["label_map"], indent=2, sort_keys=True),
        encoding="utf-8",
    )
    (args.artifacts_dir / "metrics.json").write_text(
        json.dumps(best_payload["metrics"], indent=2),
        encoding="utf-8",
    )
    print(f"saved {checkpoint_path}")


if __name__ == "__main__":
    main()
