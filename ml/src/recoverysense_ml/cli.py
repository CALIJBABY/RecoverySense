from __future__ import annotations

import argparse
import json

from .config import load_config
from .dataset import build_dataset_from_config
from .synthetic import generate_demo_data
from .training import train_from_config


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="RecoverySense ML pipeline")
    parser.add_argument("--config", default="ml/config/default.yaml")
    subparsers = parser.add_subparsers(dest="command", required=True)

    generate = subparsers.add_parser("generate-demo", help="Generate synthetic demo sensor and EMA CSV files")
    generate.add_argument("--participants", type=int, default=12)
    generate.add_argument("--minutes", type=int, default=12)

    subparsers.add_parser("build-dataset", help="Preprocess, window, label, and extract features")
    subparsers.add_parser("train", help="Train and evaluate the Random Forest model")
    subparsers.add_parser("run-demo", help="Generate demo data, build features, and train")
    return parser


def main() -> None:
    args = _parser().parse_args()
    config = load_config(args.config)

    if args.command in {"generate-demo", "run-demo"}:
        participants = getattr(args, "participants", 12)
        minutes = getattr(args, "minutes", 12)
        sensors, ema = generate_demo_data(config, participants, minutes)
        print(f"Generated {len(sensors):,} sensor rows and {len(ema):,} EMA events.")

    if args.command in {"build-dataset", "run-demo"}:
        dataset = build_dataset_from_config(config)
        print(f"Built {len(dataset):,} labeled windows with {dataset.shape[1] - 7} features.")
        print(dataset["label"].value_counts().sort_index().rename(index={0: "negative", 1: "positive"}))

    if args.command in {"train", "run-demo"}:
        _, metrics = train_from_config(config)
        print(json.dumps(metrics["test"], indent=2))
        print(f"Saved model bundle to {config['paths']['model_bundle']}")


if __name__ == "__main__":
    main()
