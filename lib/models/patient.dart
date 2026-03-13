class Patient {
  final String patientId;
  final int patientCode;
  final String name;
  final int age;
  final String gender;

  const Patient({
    required this.patientId,
    required this.patientCode,
    required this.name,
    required this.age,
    required this.gender,
  });

  factory Patient.fromJson(Map<String, dynamic> json) => Patient(
        patientId: json['patientId'] as String,
        patientCode: (json['patientCode'] as int?) ?? 0,
        name: json['name'] as String,
        age: json['age'] as int,
        gender: json['gender'] as String,
      );
}
