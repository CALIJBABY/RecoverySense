# Start Here: RecoverySense ML

The ML framework has been added and tested.

From the repository root in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup_ml.ps1
powershell -ExecutionPolicy Bypass -File scripts\run_ml_demo.ps1
```

Then start the model-backed API:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_backend.ps1
```

Complete explanation:

```text
docs/ML_FRAMEWORK_GUIDE.md
```

The included model and metrics were generated from synthetic demo data only. They prove the software runs; they do not prove real-world performance.
