class Patient {
  final String patientId;
  final String name;
  final int age;
  final String gender;

  const Patient({
    required this.patientId,
    required this.name,
    required this.age,
    required this.gender,
  });

  factory Patient.fromJson(Map<String, dynamic> json) => Patient(
        patientId: json['patientId'] as String,
        name: json['name'] as String,
        age: json['age'] as int,
        gender: json['gender'] as String,
      );
}
