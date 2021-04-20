import 'package:domain_visualiser/actions/problems/remove_problem_action.dart';
import 'package:domain_visualiser/extensions/flutter/context_extensions.dart';
import 'package:domain_visualiser/models/problems/problem.dart';
import 'package:flutter/material.dart';

/// Creates a widget to show an error from a type of [Problem].
/// The ProblemPage is used for alerting a user to an error.
class ProblemPage extends StatelessWidget {
  final Problem problem;

  const ProblemPage(this.problem);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Whoops'),
      content: SingleChildScrollView(
        child: Text(problem.errorString),
      ),
      actions: [
        OutlinedButton(
            onPressed: () =>
                context.dispatch(RemoveProblemAction(problem: problem)),
            child: Text('Dismiss'))
      ],
    );
  }
}
