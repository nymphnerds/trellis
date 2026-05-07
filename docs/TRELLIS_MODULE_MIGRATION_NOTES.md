# TRELLIS.2 Module Migration Notes

This repo is the clean module home for the current TRELLIS.2 GGUF backend.

Source copied from:

```text
/home/nymph/TRELLIS.2
```

Current source HEAD at copy time:

```text
5565d24 Release Training Code
```

The Nymphs adapter was copied from:

```text
NymphsCore/Manager/scripts/trellis_adapter/
```

## Module Identity

```text
id: trellis
name: TRELLIS.2
short name: TR
repo: github.com/nymphnerds/trellis
install path: ~/TRELLIS.2
```

## Quantized Model Pull

Main branch currently pulls quantized model files from:

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

Set this to pull all supported quantized models:

```bash
TRELLIS_GGUF_QUANT=all scripts/trellis_fetch_models.sh
```

## What Carries Over

- Microsoft TRELLIS.2 source
- `scripts/api_server_trellis_gguf.py`
- `scripts/trellis_gguf_common.py`
- GGUF runtime package pins
- support checkpoint pull from `microsoft/TRELLIS.2-4B`
- custom manager page requirement

## What Stays Out Of Git

- `.venv`
- `.cache`
- GGUF model files
- Hugging Face cache
- generated assets
- runtime logs

## Manager Migration

The current manager installer logic lives in:

```text
NymphsCore/Manager/scripts/install_trellis.sh
NymphsCore/Manager/scripts/runtime_tools_status.sh
NymphsCore/Manager/scripts/prefetch_models.sh
NymphsCore/Manager/scripts/smoke_test_server.sh
```

The module repo now owns equivalent scripts under `scripts/`.

The manager should eventually stop special-casing `install_trellis.sh` and call the module contract from `nymph.json`.

## Custom Page Rule

The TRELLIS.2 manager page should be custom, not the generic fallback facts page. The manifest tells the manager how to discover/install/run the module; it does not replace the designed module page.
