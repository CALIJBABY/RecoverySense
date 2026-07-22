# RecoverySense Runnable Starter

RecoverySense is a multi-application prototype containing a Flutter phone app, Wear OS app, FastAPI backend, Firebase scaffolding, and a wearable-sensor machine-learning pipeline.

## Main folders

```text
apps/phone_flutter_new   Current Flutter phone application
apps/wear_android       Wear OS projects
backend/api             FastAPI sensor and EMA API
firebase                Firebase configuration and rules scaffolding
ml                      End-to-end Random Forest framework
docs                    Architecture and implementation guides
scripts                 Windows setup and run scripts
```

## Run the current phone app

```powershell
cd apps\phone_flutter_new
flutter pub get
flutter run
```

## Set up and run the ML framework

From the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup_ml.ps1
powershell -ExecutionPolicy Bypass -File scripts\run_ml_demo.ps1
```

Read the complete explanation:

```text
docs/ML_FRAMEWORK_GUIDE.md
```

## Run the backend

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_backend.ps1
```

Then open:

```text
http://127.0.0.1:8000/docs
```

## Current ML decision flow

```text
30-second window -> feature extraction -> Random Forest probability
-> compare with 0.70 -> apply 15-minute cooldown -> trigger EMA
```

The generated demo model uses synthetic data only. Replace it with real sensor and EMA data before interpreting model performance.
