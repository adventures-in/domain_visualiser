import 'package:domain_visualiser/widgets/auth/auth_page.dart';
import 'package:domain_visualiser/widgets/drawing/drawing_page.dart';
import 'package:domain_visualiser/widgets/shared/error_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class InitialPageBuilder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, AsyncSnapshot<User?> snapshot) {
          if (snapshot.hasError) {
            return ErrorPage(error: snapshot.error);
          }
          if (snapshot.hasData) {
            return (snapshot.data == null) ? AuthPage() : DrawingPage();
          }
          return CircularProgressIndicator();
        });
  }
}
