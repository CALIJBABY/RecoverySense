from __future__ import annotations

import argparse
import json

from .ablation import run_ablation_from_config
from .config import load_config
from .dataset import build_dataset_from_config
from .firestore_export import export_firestore_to_csv
from .sleep_model import build_sleep_dataset_from_config, train_sleep_from_config
from .synthetic import generate_complete_demo_data
from .training import train_from_config


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="RecoverySense ML pipeline")
    parser.add_argument("--config", default="ml/config/default.yaml")
    subparsers = parser.add_subparsers(dest="command", required=True)

    generate = subparsers.add_parser(
        "generate-demo",
        help="Generate synthetic demo sensor, EMA, and sleep CSV files",
    )
    generate.add_argument("--participants", type=int, default=12)
    generate.add_argument("--minutes", type=int, default=12)

    export = subparsers.add_parser(
        "export-firestore",
        help="Export Firestore sensor, EMA, and sleep-session data",
    )
    export.add_argument("--output-dir", default="ml/data/raw")
    export.add_argument("--credentials")

    subparsers.add_parser(
        "build-dataset",
        help="Build craving-risk windows with prior sleep context",
    )
    subparsers.add_parser(
        "build-sleep-dataset",
        help="Build 30-second binary sleep/wake epochs from overnight sensor data",
    )
    subparsers.add_parser("train", help="Compare classifiers and save the best craving model")
    subparsers.add_parser(
        "train-sleep", help="Compare classifiers and save the best binary sleep/wake model"
    )
    subparsers.add_parser("ablation", help="Compare feature-group combinations")
    run_demo = subparsers.add_parser(
        "run-demo", help="Generate demo data and train craving plus sleep/wake models"
    )
    run_demo.add_argument("--participants", type=int, default=12)
    run_demo.add_argument("--minutes", type=int, default=12)
    return parser


def main() -> None:
    args = _parser().parse_args()

    if args.command == "export-firestore":
        sensor_path, ema_path, sleep_path, ppg_path = export_firestore_to_csv(
            output_dir=args.output_dir,
            credentials_path=args.credentials,
        )
        print(f"Wrote sensor data to {sensor_path}")
        print(f"Wrote EMA data to {ema_path}")
        print(f"Wrote sleep session data to {sleep_path}")
        return

    config = load_config(args.config)
    if args.command == "run-demo":
        config.setdefault("project", {})["demo_only"] = True

    if args.command in {"generate-demo", "run-demo"}:
        participants = getattr(args, "participants", 12)
        minutes = getattr(args, "minutes", 12)
        sensors, ema, sleep = generate_complete_demo_data(
            config, participants, minutes
        )
        print(
            f"Generated {len(sensors):,} sensor rows, {len(ema):,} EMA events, "
            f"and {len(sleep):,} sleep-session records."
        )

    if args.command in {"build-dataset", "run-demo"}:
        dataset = build_dataset_from_config(config)
        print(
            f"Built {len(dataset):,} labeled craving windows with "
            f"{dataset.shape[1] - 7} features."
        )
        print(
            dataset["label"]
            .value_counts()
            .sort_index()
            .rename(index={0: "negative", 1: "positive"})
        )

    if args.command in {"build-sleep-dataset", "run-demo"}:
        dataset = build_sleep_dataset_from_config(config)
        print(f"Built {len(dataset):,} 30-second sleep/wake epochs.")
        print(dataset["label"].value_counts().sort_index().rename(index={0: "wake", 1: "sleep"}))

    if args.command == "ablation":
        results = run_ablation_from_config(config)
        print(json.dumps(results["experiments"], indent=2))

    if args.command in {"train", "run-demo"}:
        _, metrics = train_from_config(config)
        best_model = metrics["best_model"]
        print(json.dumps(metrics["models"][best_model]["test"], indent=2))
        print(f"Selected craving model: {best_model}")
        print(f"Saved craving model bundle to {config['paths']['model_bundle']}")

    if args.command in {"train-sleep", "run-demo"}:
        _, metrics = train_sleep_from_config(config)
        best_model = metrics["best_model"]
        print(json.dumps(metrics["models"][best_model]["test"], indent=2))
        print(f"Selected sleep/wake model: {best_model}")
        print(f"Saved sleep model bundle to {config['paths']['sleep_model_bundle']}")


if __name__ == "__main__":
    main()
