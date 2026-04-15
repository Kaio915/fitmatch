class UserModel {
  final String name;
  final String email;
  final String type; // aluno | personal
  final String status; // pending | approved | rejected

  UserModel({
    required this.name,
    required this.email,
    required this.type,
    required this.status,
  });
}