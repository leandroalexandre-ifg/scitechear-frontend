class Participant {
  final String id;
  final String name;
  final String? voiceSamplePath;
  final int colorIndex;

  const Participant({
    required this.id,
    required this.name,
    this.voiceSamplePath,
    this.colorIndex = 0,
  });

  bool get hasVoiceSample => voiceSamplePath != null;

  Participant copyWith({String? name, String? voiceSamplePath}) => Participant(
    id: id,
    name: name ?? this.name,
    voiceSamplePath: voiceSamplePath ?? this.voiceSamplePath,
    colorIndex: colorIndex,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'voiceSamplePath': voiceSamplePath,
    'colorIndex': colorIndex,
  };

  factory Participant.fromJson(Map<String, dynamic> json) => Participant(
    id: json['id'] as String,
    name: json['name'] as String,
    voiceSamplePath: json['voiceSamplePath'] as String?,
    colorIndex: json['colorIndex'] as int? ?? 0,
  );
}
