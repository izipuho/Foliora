from __future__ import annotations

import argparse
from pathlib import Path

import coremltools as ct
import torch

from model import BellDecisionModel, CoreMLExportWrapper


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", type=Path, default=Path("ml/artifacts/bell_classifier.pt"))
    parser.add_argument("--output", type=Path, default=Path("ml/artifacts/BellTagDecisionClassifier.mlpackage"))
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    checkpoint = torch.load(args.checkpoint, map_location="cpu")
    tag_vocab = checkpoint["tag_vocab"]
    label_map = checkpoint["label_map"]
    image_size = int(checkpoint["image_size"])
    labels = [label for label, _ in sorted(label_map.items(), key=lambda item: item[1])]

    model = BellDecisionModel(
        tag_vocab_size=len(tag_vocab),
        num_classes=len(labels),
        pretrained=False,
        freeze_backbone=True,
    )
    model.load_state_dict(checkpoint["model_state"])
    model.eval()

    export_model = CoreMLExportWrapper(model).eval()
    example_image = torch.rand(1, 3, image_size, image_size)
    example_tag = torch.zeros(1, len(tag_vocab), dtype=torch.float32)
    example_confidence = torch.zeros(1, 1, dtype=torch.float32)
    traced = torch.jit.trace(export_model, (example_image, example_tag, example_confidence))

    classifier_config = ct.ClassifierConfig(
        labels,
        predicted_feature_name="decision",
        predicted_probabilities_output="probabilities",
    )
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.ImageType(name="image", shape=example_image.shape, scale=1.0 / 255.0),
            ct.TensorType(name="tagOneHot", shape=example_tag.shape),
            ct.TensorType(name="confidence", shape=example_confidence.shape),
        ],
        outputs=[ct.TensorType(name="probabilities")],
        classifier_config=classifier_config,
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS16,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(args.output)
    print(f"saved {args.output}")


if __name__ == "__main__":
    main()
