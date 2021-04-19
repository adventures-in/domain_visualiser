import 'package:flutter/material.dart';

/// This widget just displays the available info if there is an error.
class ErrorPage extends StatelessWidget {
  final dynamic _error;
  final StackTrace? _trace;
  const ErrorPage({
    required dynamic error,
    StackTrace? trace,
    Key? key,
  })  : _error = error,
        _trace = trace,
        super(key: key);
  @override
  Widget build(BuildContext context) {
    return Material(
      child: SingleChildScrollView(
        child: ListBody(
          children: <Widget>[
            SizedBox(height: 50),
            Text('Looks like there was a problem.',
                textDirection: TextDirection.ltr),
            SizedBox(height: 20),
            Text(_error.toString(), textDirection: TextDirection.ltr),
            SizedBox(height: 50),
            Text(_trace?.toString() ?? '', textDirection: TextDirection.ltr),
          ],
        ),
      ),
    );
  }
}
