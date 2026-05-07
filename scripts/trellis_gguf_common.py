import glob
import json
import os
import shutil
import sys
import types
from importlib.util import find_spec
from pathlib import Path

GGUF_MODEL_REPO_ID = "Aero-Ex/Trellis2-GGUF"
TRELLIS_SUPPORT_MODEL_REPO_ID = "microsoft/TRELLIS.2-4B"
TRELLIS_SUPPORT_MODEL_CACHE_DIR = "models--microsoft--TRELLIS.2-4B"
DEFAULT_GGUF_QUANT = "Q5_K_M"
VALID_GGUF_QUANTS = {"Q4_K_M", "Q5_K_M", "Q6_K", "Q8_0"}
REQUIRED_SUPPORT_MODEL_BASENAMES = {"shape_enc_next_dc_f16c32_fp16"}

os.environ.setdefault("OPENCV_IO_ENABLE_OPENEXR", "1")
os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")
os.environ.setdefault("HF_HUB_DISABLE_XET", "1")
os.environ.setdefault("HF_HUB_ENABLE_HF_TRANSFER", "0")


def module_available(module_name: str) -> bool:
    return find_spec(module_name) is not None


def preferred_attention_backend() -> str:
    if module_available("flash_attn"):
        return "flash_attn"
    if module_available("flash_attn_interface"):
        return "flash_attn_3"
    return "sdpa"


if "ATTN_BACKEND" not in os.environ:
    os.environ["ATTN_BACKEND"] = preferred_attention_backend()
if "SPARSE_ATTN_BACKEND" not in os.environ:
    os.environ["SPARSE_ATTN_BACKEND"] = os.environ["ATTN_BACKEND"]


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def resolve_gguf_quant(raw: str | None = None) -> str:
    quant = (raw or os.environ.get("TRELLIS_GGUF_QUANT") or DEFAULT_GGUF_QUANT).strip()
    if quant not in VALID_GGUF_QUANTS:
        raise RuntimeError(f"Unsupported TRELLIS GGUF quant: {quant}")
    return quant


def _hf_cache_repo_dir(repo_id: str) -> Path:
    return Path.home() / ".cache" / "huggingface" / "hub" / f"models--{repo_id.replace('/', '--')}"


def _candidate_gguf_roots() -> list[Path]:
    roots: list[Path] = []
    configured = (os.environ.get("TRELLIS_GGUF_MODEL_ROOT") or "").strip()
    if configured:
        roots.append(Path(configured).expanduser())

    legacy = repo_root() / "models" / "trellis2-gguf"
    roots.append(legacy)

    snapshots = _hf_cache_repo_dir(GGUF_MODEL_REPO_ID) / "snapshots"
    if snapshots.exists():
        roots.extend(sorted((path for path in snapshots.iterdir() if path.is_dir()), reverse=True))

    seen: set[Path] = set()
    unique: list[Path] = []
    for root in roots:
        resolved = root.resolve() if root.exists() else root
        if resolved not in seen:
            unique.append(root)
            seen.add(resolved)
    return unique


def gguf_quant_is_available(model_root: Path, quant: str, *, include_texture: bool = True) -> bool:
    quant = resolve_gguf_quant(quant)
    if not model_root.exists() or not (model_root / "pipeline.json").exists():
        return False

    required_dirs = ["shape", "refiner"]
    if include_texture:
        required_dirs.append("texture")
    for dirname in required_dirs:
        if not list((model_root / dirname).glob(f"*_{quant}.gguf")):
            return False
    return True


def available_gguf_quants(*, include_texture: bool = True) -> list[str]:
    available: set[str] = set()
    for root in _candidate_gguf_roots():
        for quant in VALID_GGUF_QUANTS:
            if gguf_quant_is_available(root, quant, include_texture=include_texture):
                available.add(quant)
    return sorted(available)


def resolve_gguf_model_root(*, local_files_only: bool = True, quant: str | None = None, include_texture: bool = True) -> Path:
    configured = (os.environ.get("TRELLIS_GGUF_MODEL_ROOT") or "").strip()
    if configured:
        configured_path = Path(configured).expanduser()
        if configured_path.exists():
            return configured_path
        return _snapshot_download(configured, local_files_only=local_files_only, quant=quant, include_texture=include_texture)

    legacy = repo_root() / "models" / "trellis2-gguf"
    if legacy.exists():
        return legacy

    return _snapshot_download(GGUF_MODEL_REPO_ID, local_files_only=local_files_only, quant=quant, include_texture=include_texture)


def _snapshot_download(repo_id: str, *, local_files_only: bool, quant: str | None, include_texture: bool) -> Path:
    from huggingface_hub import snapshot_download

    quant = resolve_gguf_quant(quant)
    allow_patterns = [
        "pipeline.json",
        "Vision/**",
        "decoders/**/*.json",
        "decoders/**/*.safetensors",
        "encoders/**/*.json",
        "encoders/**/*.safetensors",
        "refiner/*.json",
        f"refiner/*_{quant}.gguf",
        "shape/*.json",
        f"shape/*_{quant}.gguf",
    ]
    if include_texture:
        allow_patterns.extend(
            [
                "texturing_pipeline.json",
                "texture/*.json",
                f"texture/*_{quant}.gguf",
            ]
        )

    return Path(
        snapshot_download(
            repo_id=repo_id,
            local_files_only=local_files_only,
            allow_patterns=allow_patterns,
        )
    )


def _find_hf_snapshot_file(repo_dir_name: str, relative_path: str) -> str | None:
    cache_root = Path.home() / ".cache" / "huggingface" / "hub" / repo_dir_name / "snapshots"
    if not cache_root.exists():
        return None
    for snapshot in sorted(cache_root.iterdir(), reverse=True):
        candidate = snapshot / relative_path
        if candidate.exists():
            return str(candidate)
    return None


def _resolve_required_support_model(basename: str, *, local_files_only: bool = False) -> tuple[str, str]:
    relative_config = f"ckpts/{basename}.json"
    relative_model = f"ckpts/{basename}.safetensors"
    config_file = _find_hf_snapshot_file(TRELLIS_SUPPORT_MODEL_CACHE_DIR, relative_config)
    model_file = _find_hf_snapshot_file(TRELLIS_SUPPORT_MODEL_CACHE_DIR, relative_model)
    if config_file and model_file:
        return config_file, model_file

    from huggingface_hub import snapshot_download

    snapshot_dir = Path(
        snapshot_download(
            repo_id=TRELLIS_SUPPORT_MODEL_REPO_ID,
            allow_patterns=[relative_config, relative_model],
            local_files_only=local_files_only,
        )
    )
    config_path = snapshot_dir / relative_config
    model_path = snapshot_dir / relative_model
    if config_path.exists() and model_path.exists():
        return str(config_path), str(model_path)
    raise FileNotFoundError(
        f"Cannot resolve required TRELLIS GGUF support model {basename} "
        f"from {TRELLIS_SUPPORT_MODEL_REPO_ID}"
    )


def ensure_required_support_models(*, local_files_only: bool = False) -> list[tuple[str, str]]:
    return [
        _resolve_required_support_model(basename, local_files_only=local_files_only)
        for basename in sorted(REQUIRED_SUPPORT_MODEL_BASENAMES)
    ]


def prepare_dinov3_dir(model_root: Path) -> str | None:
    vision_dir = model_root / "Vision"
    src = vision_dir / "dinov3-vitl16-pretrain-lvd1689m.safetensors"
    if not src.exists():
        return None

    dst = vision_dir / "model.safetensors"
    if not dst.exists():
        try:
            os.link(str(src), str(dst))
        except OSError:
            shutil.copy2(str(src), str(dst))

    config_json = vision_dir / "config.json"
    if not config_json.exists():
        cfg = {
            "model_type": "dinov3_vit",
            "architectures": ["DINOv3ViTModel"],
            "image_size": 224,
            "patch_size": 16,
            "num_channels": 3,
            "hidden_size": 1024,
            "intermediate_size": 4096,
            "num_hidden_layers": 24,
            "num_attention_heads": 16,
            "hidden_act": "gelu",
            "attention_dropout": 0.0,
            "layer_norm_eps": 1e-5,
            "layerscale_value": 1.0,
            "drop_path_rate": 0.0,
            "use_gated_mlp": False,
            "rope_theta": 100.0,
            "query_bias": True,
            "key_bias": False,
            "value_bias": True,
            "proj_bias": True,
            "mlp_bias": True,
            "num_register_tokens": 4,
            "pos_embed_shift": None,
            "pos_embed_jitter": None,
            "pos_embed_rescale": 2.0,
            "apply_layernorm": True,
            "reshape_hidden_states": True,
            "out_features": ["stage24"],
            "out_indices": [24],
            "stage_names": ["stem"] + [f"stage{i}" for i in range(1, 25)],
        }
        config_json.write_text(json.dumps(cfg, indent=2))

    return str(vision_dir)


def install_standalone_comfy_stubs(model_root: Path) -> None:
    def stub(name: str, **attrs) -> None:
        if name not in sys.modules:
            module = types.ModuleType(name)
            for key, value in attrs.items():
                setattr(module, key, value)
            sys.modules[name] = module

    models_dir = str(model_root)
    stub(
        "folder_paths",
        models_dir=models_dir,
        get_filename_list=lambda *args, **kwargs: [],
        get_full_path=lambda *args, **kwargs: None,
        get_input_directory=lambda: "",
        get_output_directory=lambda: "",
    )

    class ProgressBar:
        def __init__(self, total=100):
            self.total = total

        def update(self, val=1):
            return None

        def update_absolute(self, val, total=None, preview=None):
            return None

    stub("comfy.utils", ProgressBar=ProgressBar)
    stub("comfy", utils=sys.modules["comfy.utils"])

    if "trellis2_model_manager" not in sys.modules:
        manager = types.ModuleType("trellis2_model_manager")

        def resolve_local_path(basename, enable_gguf=False, gguf_quant="Q8_0", precision=None):
            if enable_gguf:
                pattern = os.path.join(models_dir, "**", f"{basename}_{gguf_quant}.gguf")
                hits = glob.glob(pattern, recursive=True)
                if hits:
                    model_file = hits[0]
                    config_file = model_file.replace(f"_{gguf_quant}.gguf", ".json")
                    if not os.path.exists(config_file):
                        config_file = os.path.join(os.path.dirname(model_file), basename + ".json")
                    return config_file, model_file, True

            suffix = f"_{precision}" if precision else ""
            pattern = os.path.join(models_dir, "**", f"{basename}{suffix}.safetensors")
            hits = glob.glob(pattern, recursive=True)
            matched_suffix = suffix
            if not hits:
                pattern = os.path.join(models_dir, "**", f"{basename}.safetensors")
                hits = glob.glob(pattern, recursive=True)
                matched_suffix = ""
            if hits:
                model_file = hits[0]
                config_file = model_file.replace(f"{matched_suffix}.safetensors", ".json")
                if not os.path.exists(config_file):
                    config_file = os.path.join(os.path.dirname(model_file), basename + ".json")
                return config_file, model_file, False
            if basename in REQUIRED_SUPPORT_MODEL_BASENAMES:
                try:
                    config_file, model_file = _resolve_required_support_model(basename, local_files_only=True)
                except Exception as exc:
                    raise FileNotFoundError(
                        f"Required TRELLIS.2 GGUF support checkpoint {basename} is not installed. "
                        "Open NymphsCore Manager > Runtime Tools and fetch/repair TRELLIS.2 GGUF models before retexturing."
                    ) from exc
                return config_file, model_file, False
            raise FileNotFoundError(
                f"Cannot resolve TRELLIS GGUF model {basename} "
                f"(gguf={enable_gguf}, quant={gguf_quant}, precision={precision}) in {models_dir}"
            )

        manager.resolve_local_path = resolve_local_path
        manager.ensure_model_files = lambda: None
        sys.modules["trellis2_model_manager"] = manager


def patch_hf_local_path_validation() -> None:
    try:
        import huggingface_hub.utils._validators as validators

        original = validators.validate_repo_id

        def patched(repo_id, *args, **kwargs):
            if os.path.isabs(str(repo_id)) or os.path.exists(str(repo_id)):
                return
            return original(repo_id, *args, **kwargs)

        validators.validate_repo_id = patched
    except Exception:
        return


def patch_o_voxel_tiled_converter() -> None:
    try:
        import o_voxel.convert as convert
    except Exception:
        return

    if hasattr(convert, "tiled_flexible_dual_grid_to_mesh"):
        return
    if not hasattr(convert, "flexible_dual_grid_to_mesh"):
        return

    def tiled_flexible_dual_grid_to_mesh(*args, **kwargs):
        kwargs.pop("tile_size", None)
        return convert.flexible_dual_grid_to_mesh(*args, **kwargs)

    convert.tiled_flexible_dual_grid_to_mesh = tiled_flexible_dual_grid_to_mesh


def patch_trellis2_gguf_dinov3() -> None:
    import torch

    from trellis2_gguf.modules import image_feature_extractor

    def patched_dino_extract_features(self, image: torch.Tensor) -> torch.Tensor:
        from torch.nn import functional as F

        image = image.to(self.model.embeddings.patch_embeddings.weight.dtype)
        hidden_states = self.model.embeddings(image, bool_masked_pos=None)
        position_embeddings = self.model.rope_embeddings(image)

        layers = self.model.layer if hasattr(self.model, "layer") else self.model.model.layer
        for layer_module in layers:
            hidden_states = layer_module(
                hidden_states,
                position_embeddings=position_embeddings,
            )

        return F.layer_norm(hidden_states, hidden_states.shape[-1:])

    image_feature_extractor.DinoV3FeatureExtractor.extract_features = patched_dino_extract_features


def ensure_trellis2_gguf_ready(model_root: Path) -> None:
    import torch  # noqa: F401

    install_standalone_comfy_stubs(model_root)
    patch_hf_local_path_validation()
    patch_o_voxel_tiled_converter()
    try:
        from trellis2_gguf.pipelines import Trellis2ImageTo3DPipeline  # noqa: F401
        patch_trellis2_gguf_dinov3()
    except ImportError as exc:
        raise RuntimeError(
            "trellis2_gguf is not installed in this TRELLIS runtime. "
            "Install the GGUF runtime dependencies before starting TRELLIS.2 GGUF."
        ) from exc
