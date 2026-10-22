# Third-Party Licenses

LessonLens uses the following open-source dependencies. Their respective licenses are listed below.

## Swift Dependencies (macOS App)

| Package | License | Source |
|---------|---------|--------|
| WhisperKit | MIT | https://github.com/argmaxinc/WhisperKit |
| swift-argument-parser | Apache 2.0 | https://github.com/apple/swift-argument-parser |
| swift-collections | Apache 2.0 | https://github.com/apple/swift-collections |
| swift-jinja | Apache 2.0 | https://github.com/huggingface/swift-jinja |
| swift-transformers | Apache 2.0 | https://github.com/huggingface/swift-transformers |

## JavaScript Dependencies (Backend)

| Package | License | Source |
|---------|---------|--------|
| hono | MIT | https://github.com/honojs/hono |
| jose | MIT | https://github.com/panva/jose |
| typescript | Apache 2.0 | https://github.com/microsoft/TypeScript |

## Bundled Assets (macOS App)

| Asset | License | Copyright / Source |
|-------|---------|--------------------|
| Whisper base speech model (`Resources/Models/openai_whisper-base`, Core ML conversion of `openai/whisper-base` for WhisperKit) | MIT | Copyright (c) 2022 OpenAI. OpenAI's repository states that "Whisper's code and model weights are released under the MIT License" (https://github.com/openai/whisper); the Hugging Face model card for `openai/whisper-base` lists Apache 2.0. Core ML conversion by Argmax, MIT per https://huggingface.co/argmaxinc/whisperkit-coreml |
| Josefin Sans Bold (`Resources/Fonts/JosefinSans-Bold.ttf`) | SIL Open Font License 1.1 | Copyright 2010 The Josefin Sans Project Authors (https://github.com/ThomasJockin/JosefinSansFont-master), with Reserved Font Name "Josefin Sans" |
| Josefin Slab Regular and Bold (`Resources/Fonts/JosefinSlab-*.ttf`) | SIL Open Font License 1.1 | Copyright 2020 The Josefin Slab Project Authors (https://github.com/googlefonts/josefinslab/); Copyright (c) 2010, Santiago Orozco, with Reserved Font Name Josefin |

The fonts' copyright notices and the full SIL Open Font License 1.1 text are in `LessonLens/LessonLens/Resources/Fonts/OFL.txt`, which ships inside the app bundle alongside the fonts, as the license requires.

## Runtime

| Tool | License | Source |
|------|---------|--------|
| Bun | MIT | https://github.com/oven-sh/bun |
