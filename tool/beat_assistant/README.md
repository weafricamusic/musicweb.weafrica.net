# WeAfrica AI Beat Assistant — v1 (Free)

This is the **first step**: the app/backend provides **artist-friendly presets** and generates a high-quality prompt.
Actual audio generation happens in **Google Colab** using Meta's open-source MusicGen (AudioCraft).

## Colab quickstart

In a Colab notebook cell:

```python
!pip -q install audiocraft

from audiocraft.models import MusicGen
from audiocraft.data.audio import audio_write

model = MusicGen.get_pretrained("small")
model.set_generation_params(duration=30)  # seconds

descriptions = [
    "Afrobeats instrumental, African rhythm, energetic drums, club vibe, 120 bpm"
]

wav = model.generate(descriptions)

audio_write("weafrica_beat", wav[0].cpu(), model.sample_rate)
print("Saved weafrica_beat.wav")
```

## WeAfrica presets (examples)

- Afrobeats: `bpm=120`, `mood=happy`, duration 30s
- Amapiano: `bpm=112`, `mood=groovy`, duration 30s
- Dancehall: `bpm=132`, `mood=aggressive`, duration 30s

## Prompting tips (African flavor)

- "Malawian Afrobeat with traditional percussion, bright shakers, 120 bpm"
- "Amapiano groove, deep log drum, slow build, township vibe, 112 bpm"
- "Dancehall African fusion, aggressive bass, hype drops, 132 bpm"

## App/backend integration

- `GET /api/beat/presets` returns preset objects (style/bpm/mood/duration + base prompt).
- `POST /api/beat/generate` returns a final `prompt` and optional `colab_markdown` you can show in-app.

Later upgrade path:
- Run generation on a GPU worker (Cloud Run / Modal / Replicate)
- Store results in Supabase Storage and return a download URL
