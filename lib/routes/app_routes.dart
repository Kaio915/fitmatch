import 'package:flutter/material.dart';
import '../views/home_view.dart';
import '../views/register_student_view.dart';
import '../views/register_trainer_view.dart';
class AppRoutes {
  static const home = '/';

  static const registerStudent = '/register-student';
  static const registerTrainer = '/register-trainer';

  static Map<String, WidgetBuilder> routes = {
    home: (_) => const HomeView(),
    registerStudent: (_) => const RegisterStudentView(),
    registerTrainer: (_) => const RegisterTrainerView(),
  };
}
