from __future__ import annotations

import argparse
import json
from pathlib import Path

import coremltools as ct
import numpy as np
from PIL import Image

from dataset import LABELS, build_tag_vocab, load_annotations


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset-dir", type=Path, default=Path("Example photos/dataset"))
    parser.add_argument("--model", type=Path, default=Path("ml/artifacts/BellTagDecisionClassifier.mlpackage"))
    parser.add_argument("--tag-vocab", type=Path, default=Path("ml/artifacts/tag_vocab.json"))
    parser.add_argument("--limit", type=int, default=20)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    rows = load_annotations(args.dataset_dir)
    tag_vocab = json.loads(args.tag_vocab.read_text(encoding="utf-8")) if args.tag_vocab.exists() else build_tag_vocab(rows)
    model = ct.models.MLModel(str(args.model))

    correct = 0
    total = 0
    for row in rows[: args.limit]:
        image = Image.open(args.dataset_dir / "crops" / row.crop_file_name).convert("RGB").resize((224, 224))
        tag_one_hot = np.zeros((1, len(tag_vocab)), dtype=np.float32)
        tag_one_hot[0, tag_vocab.get(row.tag, tag_vocab["<UNK>"])] = 1.0
        confidence = np.array([[max(0.0, min(1.0, row.confidence))]], dtype=np.float32)
        result = model.predict(
            {
                "image": image,
                "tagOneHot": tag_one_hot,
                "confidence": confidence,
            }
        )
        predicted = result["decision"]
        correct += int(predicted == row.decision)
        total += 1
        print(f"{predicted:12s} actual={row.decision:12s} tag={row.tag}")

    print(f"accuracy_on_first_{total}={correct / max(1, total):.4f} labels={LABELS}")


if __name__ == "__main__":
    main()
