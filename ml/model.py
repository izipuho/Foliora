from __future__ import annotations

import torch
from torch import nn
from torchvision.models import MobileNet_V3_Small_Weights, mobilenet_v3_small


class BellDecisionModel(nn.Module):
    def __init__(
        self,
        tag_vocab_size: int,
        num_classes: int = 3,
        tag_dim: int = 32,
        confidence_dim: int = 8,
        hidden_dim: int = 128,
        dropout: float = 0.2,
        pretrained: bool = False,
        freeze_backbone: bool = True,
    ) -> None:
        super().__init__()
        weights = MobileNet_V3_Small_Weights.DEFAULT if pretrained else None
        backbone = mobilenet_v3_small(weights=weights)
        image_dim = backbone.classifier[0].in_features
        backbone.classifier = nn.Identity()
        self.image_encoder = backbone

        if freeze_backbone:
            for parameter in self.image_encoder.parameters():
                parameter.requires_grad = False

        self.tag_branch = nn.Sequential(
            nn.Linear(tag_vocab_size, tag_dim),
            nn.ReLU(inplace=True),
        )
        self.confidence_branch = nn.Sequential(
            nn.Linear(1, confidence_dim),
            nn.ReLU(inplace=True),
        )
        self.classifier = nn.Sequential(
            nn.Linear(image_dim + tag_dim + confidence_dim, hidden_dim),
            nn.ReLU(inplace=True),
            nn.Dropout(dropout),
            nn.Linear(hidden_dim, num_classes),
        )

        self.register_buffer(
            "image_mean",
            torch.tensor([0.485, 0.456, 0.406], dtype=torch.float32).view(1, 3, 1, 1),
        )
        self.register_buffer(
            "image_std",
            torch.tensor([0.229, 0.224, 0.225], dtype=torch.float32).view(1, 3, 1, 1),
        )

    def forward(
        self,
        image: torch.Tensor,
        tag_one_hot: torch.Tensor,
        confidence: torch.Tensor,
    ) -> torch.Tensor:
        image = (image - self.image_mean) / self.image_std
        image_features = self.image_encoder(image)
        tag_features = self.tag_branch(tag_one_hot)
        confidence_features = self.confidence_branch(confidence)
        features = torch.cat([image_features, tag_features, confidence_features], dim=1)
        return self.classifier(features)


class CoreMLExportWrapper(nn.Module):
    def __init__(self, model: BellDecisionModel) -> None:
        super().__init__()
        self.model = model

    def forward(
        self,
        image: torch.Tensor,
        tag_one_hot: torch.Tensor,
        confidence: torch.Tensor,
    ) -> torch.Tensor:
        logits = self.model(image, tag_one_hot, confidence)
        return torch.softmax(logits, dim=1)
