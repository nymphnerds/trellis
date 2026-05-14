# TRELLIS.2 GGUF

TRELLIS.2 GGUF is the NymphsCore 3D generation backend packaged as an installable Nymph module.

It combines:

- Microsoft `TRELLIS.2` source
- the NymphsCore local HTTP adapter
- GGUF model loading through `ComfyUI-Trellis2-GGUF`
- shape and textured asset generation
- module-owned manager scripts for install, status, launch, logs, model fetch,
  smoke testing, and uninstall

This repo follows the NymphsCore module-owned backend pattern. The Manager stays
generic: it renders the native manifest-declared controls and runs the installed
module scripts.

## Runtime Layout

Expected in-distro layout:

- module repo: `~/TRELLIS.2`
- runtime venv: `~/TRELLIS.2/.venv`
- adapter scripts: `~/TRELLIS.2/scripts/`
- runtime helper cache: `~/TRELLIS.2/.cache/trellis-gguf-runtime`
- logs: `~/NymphsData/logs/trellis`
- outputs: `~/NymphsData/outputs/trellis`
- config/preset: `~/NymphsData/config/trellis/model-preset.env`
- Hugging Face cache: `~/NymphsData/cache/huggingface`
- rembg u2net model: `~/NymphsData/models/rembg/u2net.onnx`

## Manager Contract

The manager discovers this module through `nymph.json`.

Useful scripts:

```bash
scripts/install_trellis.sh
scripts/trellis_status.sh
scripts/trellis_start.sh
scripts/trellis_stop.sh
scripts/trellis_open.sh
scripts/trellis_logs.sh
scripts/trellis_fetch_models.sh
scripts/trellis_smoke_test.sh
scripts/trellis_uninstall.sh
```

Default local URL:

```text
http://127.0.0.1:8095
```

## Quantized Model Pull

The module pulls TRELLIS.2 GGUF models from:

```text
Aero-Ex/Trellis2-GGUF
```

Supported quants:

```text
Q4_K_M
Q5_K_M
Q6_K
Q8_0
```

Default quant:

```text
Q5_K_M
```

To pull every supported quant:

```bash
scripts/trellis_fetch_models.sh --quant all
```

Support checkpoints are pulled from:

```text
microsoft/TRELLIS.2-4B
```

`Fetch Models` also downloads the `rembg` u2net background-removal model from
the upstream release artifact used by the previous main-branch runtime flow.

## Important Dependency Pins

The module tracks the working main-branch manager pins:

```text
microsoft/TRELLIS.2: 5565d240c4a494caaf9ece7a554542b76ffa36d3
ComfyUI-Trellis2-GGUF: ed7245cba449c79e0a6703b7f09c0590328b4f77
ComfyUI-GGUF: 6ea2651e7df66d7585f6ffee804b20e92fb38b8a
utils3d: 9a4eb15e4021b67b12c460c7057d642626897ec8
CuMesh: cf1a2f07304b5fe388ed86a16e4a0474599df914
FlexGEMM: 6dd94a859c26ee8246888502eada3dd8ad85532e
nvdiffrast: 253ac4fcea7de5f396371124af597e6cc957bfae
```

## Repo Rule

This repo should stay clean:

- keep source code, scripts, docs, and `nymph.json`
- do not commit `.venv`
- do not commit `.cache`
- do not commit GGUF model files
- do not commit generated GLB/PLY/OBJ assets
- do not commit runtime logs
- keep reusable models, logs, outputs, and config under `~/NymphsData`

## Upstream

This module includes Microsoft TRELLIS.2 source. See `LICENSE` and `SECURITY.md` for upstream terms and reporting guidance.
