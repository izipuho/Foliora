from __future__ import annotations

import json
import random
from dataclasses import dataclass
from pathlib import Path

import torch
from PIL import Image
from torch.utils.data import Dataset
from torchvision import transforms


LABELS = ["keep", "rejectNoise", "rejectWrong"]
UNK_TAG = "<UNK>"


@dataclass(frozen=True)
class Annotation:
    crop_file_name: str
    tag: str
    confidence: float
    decision: str
    photo_id: str


def load_annotations(dataset_dir: Path) -> list[Annotation]:
    annotations_path = dataset_dir / "annotations.jsonl"
    rows: list[Annotation] = []
    with annotations_path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            raw = json.loads(line)
            try:
                rows.append(
                    Annotation(
                        crop_file_name=raw["cropFileName"],
                        tag=raw["tag"],
                        confidence=float(raw["confidence"]),
                        decision=raw["decision"],
                        photo_id=raw["photoID"],
                    )
                )
            except KeyError as error:
                raise ValueError(f"Missing {error} in {annotations_path}:{line_number}") from error

    missing = [row.decision for row in rows if row.decision not in LABELS]
    if missing:
        raise ValueError(f"Unknown decisions: {sorted(set(missing))}")
    return rows


def validate_crops(dataset_dir: Path, rows: list[Annotation]) -> None:
    missing = sorted(
        {
            row.crop_file_name
            for row in rows
            if not (dataset_dir / "crops" / row.crop_file_name).is_file()
        }
    )
    if missing:
        preview = ", ".join(missing[:5])
        raise FileNotFoundError(f"Missing {len(missing)} crop files, first: {preview}")


def build_tag_vocab(rows: list[Annotation]) -> dict[str, int]:
    tags = sorted({row.tag for row in rows})
    return {tag: index for index, tag in enumerate([UNK_TAG, *tags])}


def split_by_photo_id(
    rows: list[Annotation],
    val_ratio: float,
    seed: int,
) -> tuple[list[Annotation], list[Annotation]]:
    photo_ids = sorted({row.photo_id for row in rows})
    rng = random.Random(seed)
    rng.shuffle(photo_ids)
    val_count = max(1, int(round(len(photo_ids) * val_ratio))) if len(photo_ids) > 1 else 0
    val_ids = set(photo_ids[:val_count])
    train_rows = [row for row in rows if row.photo_id not in val_ids]
    val_rows = [row for row in rows if row.photo_id in val_ids]
    return train_rows, val_rows


def image_transform(image_size: int, train: bool) -> transforms.Compose:
    steps: list[object] = [
        transforms.Resize((image_size, image_size)),
    ]
    if train:
        steps.extend(
            [
                transforms.RandomRotation(8),
                transforms.ColorJitter(brightness=0.15, contrast=0.15, saturation=0.1),
            ]
        )
    steps.append(transforms.ToTensor())
    return transforms.Compose(steps)


class BellDecisionDataset(Dataset[tuple[torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor]]):
    def __init__(
        self,
        dataset_dir: Path,
        rows: list[Annotation],
        tag_vocab: dict[str, int],
        label_map: dict[str, int],
        image_size: int,
        train: bool,
    ) -> None:
        self.dataset_dir = dataset_dir
        self.rows = rows
        self.tag_vocab = tag_vocab
        self.label_map = label_map
        self.transform = image_transform(image_size, train=train)

    def __len__(self) -> int:
        return len(self.rows)

    def __getitem__(self, index: int) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor]:
        row = self.rows[index]
        image_path = self.dataset_dir / "crops" / row.crop_file_name
        image = Image.open(image_path).convert("RGB")
        image_tensor = self.transform(image)

        tag_one_hot = torch.zeros(len(self.tag_vocab), dtype=torch.float32)
        tag_one_hot[self.tag_vocab.get(row.tag, self.tag_vocab[UNK_TAG])] = 1.0

        confidence = torch.tensor([[max(0.0, min(1.0, row.confidence))]], dtype=torch.float32).view(1)
        label = torch.tensor(self.label_map[row.decision], dtype=torch.long)
        return image_tensor, tag_one_hot, confidence, label
