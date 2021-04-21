import 'package:domain_visualiser/models/app-state/app_state.dart';
import 'package:domain_visualiser/models/domain-objects/class_box.dart';
import 'package:domain_visualiser/widgets/drawing/drawing_canvas.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

class DrawingPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, IList<ClassBox>>(
        distinct: true,
        converter: (store) => store.state.classBoxes,
        builder: (context, boxes) => DrawingCanvas(boxes.unlockView));
  }
}
