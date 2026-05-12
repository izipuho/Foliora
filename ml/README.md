# Bell Tag Decision Classifier

Local multimodal training pipeline:

```text
crop image + tag text + vision confidence -> keep / rejectNoise / rejectWrong
```

The model does not use Foundation Models or cloud APIs. It trains in PyTorch and exports a Core ML `.mlpackage`.

## Setup

```sh
python3 -m venv .venv-ml
source .venv-ml/bin/activate
pip install -r ml/requirements.txt
```

## Train

```sh
python ml/train.py --dataset-dir "Example photos/dataset"
```

Artifacts:

```text
ml/artifacts/bell_classifier.pt
ml/artifacts/tag_vocab.json
ml/artifacts/label_map.json
ml/artifacts/metrics.json
```

By default the image backbone is frozen. If cached torchvision weights are available and you want transfer learning, use:

```sh
python ml/train.py --dataset-dir "Example photos/dataset" --pretrained
```

## Export Core ML

```sh
python ml/export_coreml.py
```

Output:

```text
ml/artifacts/BellTagDecisionClassifier.mlpackage
```

## Core ML Inputs

```text
image: RGB image, 224x224
tagOneHot: Float32[1, tag_vocab_size]
confidence: Float32[1, 1]
```

Outputs:

```text
decision: keep / rejectNoise / rejectWrong
probabilities: class probabilities
```

Swift runtime should bundle `tag_vocab.json` with the model and convert each candidate tag into a one-hot vector before prediction.
