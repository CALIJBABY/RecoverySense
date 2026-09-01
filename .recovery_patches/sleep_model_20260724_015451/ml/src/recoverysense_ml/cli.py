from __future__ import annotations

import argparse
import json

from .ablation import run_ablation_from_config
from .config import load_config
from .dataset import build_dataset_from_config
from .firestore_export import export_firestore_to_csv
from .synthetic import generate_demo_data
from .training import train_from_config


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="RecoverySense ML pipeline")
    parser.add_argument("--config", default="ml/config/default.yaml")
    subparsers = parser.add_subparsers(dest="command", required=True)

    generate = subparsers.add_parser(
        "generate-demo",
        help="Generate synthetic demo sensor and EMA CSV files",
    )
    generate.add_argument("--participants", type=int, default=12)
    generate.add_argument("--minutes", type=int, default=12)

    export = subparsers.add_parser(
        "export-firestore",
        help="Export Firestore sensor batches and EMA events to ML-ready CSV files",
    )
    export.add_argument("--output-dir", default="ml/data/raw")
    export.add_argument("--credentials")

    subparsers.add_parser(
        "build-dataset",
        help="Preprocess, window, label, and extract features",
    )
    subparsers.add_parser("train", help="Compare classifiers and save the best craving model")
    subparsers.add_parser("ablation", help="Compare feature-group combinations")
    run_demo = subparsers.add_parser("run-demo", help="Generate demo data, build features, and train")
    run_demo.add_argument("--participants", type=int, default=12)
    run_demo.add_argument("--minutes", type=int, default=12)
    return parser


def main() -> None:
    args = _parser().parse_args()

    if args.command == "export-firestore":
        sensor_path, ema_path = export_firestore_to_csv(
            output_dir=args.output_dir,
            credentials_path=args.credentials,
        )
        print(f"Wrote sensor data to {sensor_path}")
        print(f"Wrote EMA data to {ema_path}")
        return

    config = load_config(args.config)

    if args.command in {"generate-demo", "run-demo"}:
        participants = getattr(args, "participants", 12)
        minutes = getattr(args, "minutes", 12)
        sensors, ema = generate_demo_data(config, participants, minutes)
        print(f"Generated {len(sensors):,} sensor rows and {len(ema):,} EMA events.")

    if args.command in {"build-dataset", "run-demo"}:
        dataset = build_dataset_from_config(config)
        print(
            f"Built {len(dataset):,} labeled windows with "
            f"{dataset.shape[1] - 7} features."
        )
        print(
            dataset["label"]
            .value_counts()
            .sort_index()
            .rename(index={0: "negative", 1: "positive"})
        )

    if args.command == "ablation":
        results = run_ablation_from_config(config)
        print(json.dumps(results["experiments"], indent=2))

    if args.command in {"train", "run-demo"}:
        _, metrics = train_from_config(config)
        best_model = metrics["best_model"]
        print(json.dumps(metrics["models"][best_model]["test"], indent=2))
        print(f"Selected model: {best_model}")
        print(f"Saved model bundle to {config['paths']['model_bundle']}")


if __name__ == "__main__":
    main()
