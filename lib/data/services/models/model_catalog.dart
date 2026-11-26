import '../../models/local_model.dart';

/// Verified model library. Every size below was read from the Hugging Face
/// model API (`/api/models/<repo>?blobs=true`) on 2026-11-26. Licence and
/// language claims link to the upstream model cards.
class ModelCatalog {
  const ModelCatalog._();

  static const String apacheLicenseUrl =
      'https://www.apache.org/licenses/LICENSE-2.0';

  static const List<LocalModel> all = <LocalModel>[
    LocalModel(
      id: 'hy-mt3-1.8b-q4',
      title: 'Hy-MT3 1.8B · Q4_K_M',
      vendor: 'Tencent Hunyuan',
      repo: 'tencent/Hy-MT3-1.8B-GGUF',
      quantization: 'Q4_K_M',
      parameters: '1.8B',
      contextLength: 8192,
      licenseLabel: 'Apache-2.0',
      licenseUrl: apacheLicenseUrl,
      licenseVerified: true,
      tier: ModelTier.recommended,
      capabilities: <ModelCapability>{
        ModelCapability.translation,
        ModelCapability.chat,
      },
      files: <LocalModelFile>[
        LocalModelFile(
          fileName: 'Hy-MT3-1.8B-Q4_K_M.gguf',
          sizeBytes: 1348432160,
        ),
      ],
      burmeseEvidence: true,
      burmeseEvidenceNote:
          'Model card language table lists Burmese (`my`) among 102 languages.',
      recommendedForTranslation: true,
      notes:
          'Translation-specialised model. Card recommends temperature 0.7, '
          'top_p 0.6, top_k 20, repetition penalty 1.05, max_context 8192. '
          'Default Android choice: ~1.35 GB download, about 4 GB free RAM.',
    ),
    LocalModel(
      id: 'hy-mt3-1.8b-q8',
      title: 'Hy-MT3 1.8B · Q8_0',
      vendor: 'Tencent Hunyuan',
      repo: 'tencent/Hy-MT3-1.8B-GGUF',
      quantization: 'Q8_0',
      parameters: '1.8B',
      contextLength: 8192,
      licenseLabel: 'Apache-2.0',
      licenseUrl: apacheLicenseUrl,
      licenseVerified: true,
      tier: ModelTier.capable,
      capabilities: <ModelCapability>{
        ModelCapability.translation,
        ModelCapability.chat,
      },
      files: <LocalModelFile>[
        LocalModelFile(
          fileName: 'Hy-MT3-1.8B-Q8_0.gguf',
          sizeBytes: 1908528448,
        ),
      ],
      burmeseEvidence: true,
      burmeseEvidenceNote:
          'Model card language table lists Burmese (`my`) among 102 languages.',
      notes:
          'Higher precision version of the same translation model. Larger '
          'download, slightly more RAM, marginal gain on subtitles.',
    ),
    LocalModel(
      id: 'hy-mt3-7b-q4',
      title: 'Hy-MT3 7B · Q4_K_M',
      vendor: 'Tencent Hunyuan',
      repo: 'tencent/Hy-MT3-7B-GGUF',
      quantization: 'Q4_K_M',
      parameters: '7B',
      contextLength: 8192,
      licenseLabel: 'Apache-2.0',
      licenseUrl: apacheLicenseUrl,
      licenseVerified: true,
      tier: ModelTier.capable,
      capabilities: <ModelCapability>{
        ModelCapability.translation,
        ModelCapability.chat,
      },
      files: <LocalModelFile>[
        LocalModelFile(
          fileName: 'Hy-MT3-7B-Q4_K_M.gguf',
          sizeBytes: 5145531232,
        ),
      ],
      burmeseEvidence: true,
      burmeseEvidenceNote:
          'Same 102-language family card; Burmese (`my`) is listed.',
      recommendedForTranslation: true,
      notes:
          'Best quality that still plausibly fits an 8 GB phone, but expect '
          'slow first tokens and ~6 GB of free RAM while loaded.',
    ),
    LocalModel(
      id: 'hy-mt3-30b-a3b-iq2',
      title: 'Hy-MT3 30B-A3B · IQ2',
      vendor: 'Tencent Hunyuan',
      repo: 'tencent/Hy-MT3-30B-A3B-GGUF',
      quantization: 'IQ2',
      parameters: '30B MoE (3B active)',
      contextLength: 8192,
      licenseLabel: 'Apache-2.0',
      licenseUrl: apacheLicenseUrl,
      licenseVerified: true,
      tier: ModelTier.serverOnly,
      capabilities: <ModelCapability>{
        ModelCapability.translation,
        ModelCapability.chat,
      },
      files: <LocalModelFile>[
        LocalModelFile(
          fileName: 'Hy-MT3-30B-A3B-IQ2.gguf',
          sizeBytes: 13083836064,
        ),
      ],
      burmeseEvidence: true,
      burmeseEvidenceNote:
          'Same 102-language family card; Burmese (`my`) is listed.',
      notes:
          '13 GB weights: needs a desktop or 16-24 GB RAM machine. Not a '
          'practical phone download and not offered for Android install.',
    ),
    LocalModel(
      id: 'qwen1.5b-burmese-sft-q4',
      title: 'Qwen 1.5B Burmese SFT v2 · Q4_K_M',
      vendor: 'URajinda (GGUF by mradermacher)',
      repo: 'mradermacher/Qwen-1.5B-Burmese-SFT-v2-GGUF',
      quantization: 'Q4_K_M',
      parameters: '1.5B',
      contextLength: 32768,
      licenseLabel: 'Apache-2.0',
      licenseUrl: apacheLicenseUrl,
      licenseVerified: true,
      tier: ModelTier.recommended,
      capabilities: <ModelCapability>{
        ModelCapability.translation,
        ModelCapability.chat,
      },
      files: <LocalModelFile>[
        LocalModelFile(
          fileName: 'Qwen-1.5B-Burmese-SFT-v2.Q4_K_M.gguf',
          sizeBytes: 986046848,
        ),
      ],
      burmeseEvidence: true,
      burmeseEvidenceNote:
          'Purpose-built Burmese SFT; GGUF card carries the `burmese` and '
          '`myanmar` tags.',
      notes:
          'Small Burmese-first alternative to Hy-MT3. Quality varies by '
          'domain; no published subtitle benchmark.',
    ),
    LocalModel(
      id: 'shweyon-1.5b-q4',
      title: 'ShweYon Qwen2.5 1.5B Burmese v1.2.4 · Q4_K_M',
      vendor: 'URajinda (GGUF by mradermacher)',
      repo: 'mradermacher/ShweYon_Qwen2.5-Burmese-1.5B-v1.2.4-GGUF',
      quantization: 'Q4_K_M',
      parameters: '1.5B',
      contextLength: 32768,
      licenseLabel: 'Not declared',
      licenseUrl:
          'https://huggingface.co/URajinda/ShweYon_Qwen2.5-Burmese-1.5B-v1.2.4',
      licenseVerified: false,
      tier: ModelTier.recommended,
      capabilities: <ModelCapability>{
        ModelCapability.translation,
        ModelCapability.chat,
      },
      files: <LocalModelFile>[
        LocalModelFile(
          fileName: 'ShweYon_Qwen2.5-Burmese-1.5B-v1.2.4.Q4_K_M.gguf',
          sizeBytes: 1000359360,
        ),
      ],
      burmeseEvidence: true,
      burmeseEvidenceNote:
          'Upstream card is a Burmese model; the card says only '
          '"License: More Information Needed".',
      notes:
          'Install only if you accept the unclear upstream licence. The '
          'quantizer marks Q4_K_M as "fast, recommended".',
    ),
    LocalModel(
      id: 'qwen2.5-0.5b-burmese-q4',
      title: 'Qwen2.5 0.5B Burmese v1.1 · Q4_K_M',
      vendor: 'URajinda (GGUF by mradermacher)',
      repo: 'mradermacher/Qwen2.5-0.5B-burmese-v1.1-merged-GGUF',
      quantization: 'Q4_K_M',
      parameters: '0.5B',
      contextLength: 32768,
      licenseLabel: 'Not declared',
      licenseUrl:
          'https://huggingface.co/URajinda/Qwen2.5-0.5B-burmese-v1.1-merged',
      licenseVerified: false,
      tier: ModelTier.recommended,
      capabilities: <ModelCapability>{
        ModelCapability.translation,
        ModelCapability.chat,
      },
      files: <LocalModelFile>[
        LocalModelFile(
          fileName: 'Qwen2.5-0.5B-burmese-v1.1-merged.Q4_K_M.gguf',
          sizeBytes: 397808064,
        ),
      ],
      burmeseEvidence: true,
      burmeseEvidenceNote:
          'Merged Burmese-tuned Qwen2.5 0.5B; upstream licence not stated.',
      notes:
          'Smallest Burmese option (≈400 MB). Expect literal, inconsistent '
          'translations. Good for testing the pipeline on a low-end phone.',
    ),
    LocalModel(
      id: 'burmese-gpt-7b-q4',
      title: 'Burmese-GPT 7B 2025 · Q4_K_M',
      vendor: 'WYNN747 (GGUF by mradermacher)',
      repo: 'mradermacher/Burmese-GPT-7b_2025-GGUF',
      quantization: 'Q4_K_M',
      parameters: '7B',
      contextLength: 4096,
      licenseLabel: 'Not declared',
      licenseUrl: 'https://huggingface.co/WYNN747/Burmese-GPT-7b_2025',
      licenseVerified: false,
      tier: ModelTier.heavy,
      capabilities: <ModelCapability>{
        ModelCapability.translation,
        ModelCapability.chat,
      },
      files: <LocalModelFile>[
        LocalModelFile(
          fileName: 'Burmese-GPT-7b_2025.Q4_K_M.gguf',
          sizeBytes: 4174931712,
        ),
      ],
      burmeseEvidence: true,
      burmeseEvidenceNote:
          'Burmese-named 7B base model; no benchmark confirms translation '
          'quality and the licence/context are unverified.',
      notes:
          '4.2 GB weights, ~8 GB free RAM. Experimental: prefer Hy-MT3 unless '
          'you are testing Burmese-specific models.',
    ),
    LocalModel(
      id: 'qwen2.5-3b-instruct-q4',
      title: 'Qwen2.5 3B Instruct · Q4_K_M',
      vendor: 'Alibaba Qwen',
      repo: 'Qwen/Qwen2.5-3B-Instruct-GGUF',
      quantization: 'Q4_K_M',
      parameters: '3B',
      contextLength: 32768,
      licenseLabel: 'Qwen licence (see card)',
      licenseUrl:
          'https://huggingface.co/Qwen/Qwen2.5-3B-Instruct/blob/main/LICENSE',
      licenseVerified: true,
      tier: ModelTier.capable,
      capabilities: <ModelCapability>{
        ModelCapability.translation,
        ModelCapability.chat,
      },
      files: <LocalModelFile>[
        LocalModelFile(
          fileName: 'qwen2.5-3b-instruct-q4_k_m.gguf',
          sizeBytes: 2104932768,
        ),
      ],
      burmeseEvidence: false,
      burmeseEvidenceNote:
          'The Qwen2.5 card does not name Burmese explicitly. Multilingual '
          'generation may work but Burmese quality is unverified.',
      notes:
          'General instruct fallback, and useful for recap scripting when a '
          'translation-specialised model is not installed.',
    ),
    LocalModel(
      id: 'qwen2.5-vl-3b-q4',
      title: 'Qwen2.5-VL 3B Instruct · Q4_K_M + mmproj',
      vendor: 'Alibaba Qwen (GGUF by ggml-org)',
      repo: 'ggml-org/Qwen2.5-VL-3B-Instruct-GGUF',
      quantization: 'Q4_K_M weights + Q8_0 projector',
      parameters: '3B vision-language',
      contextLength: 32768,
      licenseLabel: 'Apache-2.0',
      licenseUrl: apacheLicenseUrl,
      licenseVerified: true,
      tier: ModelTier.heavy,
      capabilities: <ModelCapability>{
        ModelCapability.vision,
        ModelCapability.chat,
      },
      files: <LocalModelFile>[
        LocalModelFile(
          fileName: 'Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf',
          sizeBytes: 1929901056,
        ),
        LocalModelFile(
          fileName: 'mmproj-Qwen2.5-VL-3B-Instruct-Q8_0.gguf',
          sizeBytes: 844757728,
          role: ModelFileRole.projector,
        ),
      ],
      burmeseEvidence: false,
      burmeseEvidenceNote:
          'Vision model, not a translation model. It captions sampled frames; '
          'Burmese output is not guaranteed.',
      recommendedForRecap: true,
      notes:
          'Enables real image understanding for Movie Recap (frame captions). '
          '≈2.8 GB download; 6-8 GB free RAM recommended. Not a translation '
          'model.',
    ),
    LocalModel(
      id: 'qwen3-asr-0.6b-q8',
      title: 'Qwen3-ASR 0.6B · Q8_0 + audio projector',
      vendor: 'Alibaba Qwen (GGUF by ggml-org)',
      repo: 'ggml-org/Qwen3-ASR-0.6B-GGUF',
      quantization: 'Q8_0 weights + Q8_0 projector',
      parameters: '0.6B ASR',
      contextLength: 4096,
      licenseLabel: 'Apache-2.0',
      licenseUrl: apacheLicenseUrl,
      licenseVerified: true,
      tier: ModelTier.capable,
      capabilities: <ModelCapability>{ModelCapability.speechToText},
      files: <LocalModelFile>[
        LocalModelFile(
          fileName: 'Qwen3-ASR-0.6B-Q8_0.gguf',
          sizeBytes: 804749536,
        ),
        LocalModelFile(
          fileName: 'mmproj-Qwen3-ASR-0.6B-Q8_0.gguf',
          sizeBytes: 214392544,
          role: ModelFileRole.projector,
        ),
      ],
      burmeseEvidence: false,
      burmeseEvidenceNote:
          'Qwen3-ASR supports 30 languages and 22 Chinese dialects. The '
          'upstream list does NOT include Burmese, so Myanmar audio is not '
          'covered.',
      recommendedForAsr: true,
      notes:
          'Local speech-to-text used by Movie Recap for English, Chinese and '
          'the other 30 listed languages. Requires the llama.cpp audio '
          'projector (mmproj) file.',
    ),
    LocalModel(
      id: 'minimax-m2-ud-iq1s',
      title: 'MiniMax-M2 · UD-IQ1_S (multi-part)',
      vendor: 'MiniMax (GGUF by unsloth)',
      repo: 'unsloth/MiniMax-M2-GGUF',
      quantization: 'UD-IQ1_S',
      parameters: '230B MoE',
      contextLength: 196608,
      licenseLabel: 'MIT (GGUF repo card)',
      licenseUrl: 'https://opensource.org/license/mit',
      licenseVerified: true,
      tier: ModelTier.serverOnly,
      capabilities: <ModelCapability>{
        ModelCapability.translation,
        ModelCapability.chat,
      },
      files: <LocalModelFile>[
        LocalModelFile(
          fileName: 'UD-IQ1_S/MiniMax-M2-UD-IQ1_S-00001-of-00002.gguf',
          sizeBytes: 49925004768,
        ),
        LocalModelFile(
          fileName: 'UD-IQ1_S/MiniMax-M2-UD-IQ1_S-00002-of-00002.gguf',
          sizeBytes: 14051288992,
        ),
      ],
      burmeseEvidence: false,
      burmeseEvidenceNote:
          'General frontier model. No Burmese-specific evidence and no phone '
          'runtime support.',
      downloadable: false,
      notes:
          'PC/server class: ≈64 GB of weights in two shards plus very large '
          'RAM. NOT suitable for ordinary Android phones; shown for '
          'documentation and desktop use only.',
    ),
  ];

  static LocalModel? byId(String? id) {
    if (id == null) return null;
    for (final model in all) {
      if (model.id == id) return model;
    }
    return null;
  }

  static List<LocalModel> get androidDownloadable =>
      all.where((LocalModel m) => m.isAndroidFriendly).toList();

  static List<LocalModel> get translationModels => all
      .where(
        (LocalModel m) => m.capabilities.contains(ModelCapability.translation),
      )
      .toList();

  static List<LocalModel> get recapModels => all
      .where(
        (LocalModel m) =>
            m.capabilities.contains(ModelCapability.vision) ||
            m.capabilities.contains(ModelCapability.chat),
      )
      .toList();

  static List<LocalModel> get asrModels => all
      .where(
        (LocalModel m) => m.capabilities.contains(ModelCapability.speechToText),
      )
      .toList();

  static LocalModel get defaultTranslation =>
      byId('hy-mt3-1.8b-q4') ?? androidDownloadable.first;

  static LocalModel get defaultRecap =>
      byId('qwen2.5-vl-3b-q4') ?? recapModels.first;

  static LocalModel get defaultAsr =>
      byId('qwen3-asr-0.6b-q8') ?? asrModels.first;
}
