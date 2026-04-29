import 'package:flutter/material.dart';
import '../views/home_view.dart';
import '../views/register_student_view.dart';
import '../views/register_trainer_view.dart';
class AppRoutes {
  static const home = '/';

  static const registerStudent = '/register-student';
  static const registerTrainer = '/register-trainer';
  static const dietControl = '/diet-control';

  static Map<String, WidgetBuilder> routes = {
    registerStudent: (_) => const RegisterStudentView(),
    registerTrainer: (_) => const RegisterTrainerView(),
  };
}
