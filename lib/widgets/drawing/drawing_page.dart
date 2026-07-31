import 'package:codraw/actions/domain-objects/clear_class_boxes_action.dart';
import 'package:codraw/actions/shared/connect_data_stream_action.dart';
import 'package:codraw/sync/sync_section.dart';
import 'package:codraw/extensions/flutter/context_extensions.dart';
import 'package:codraw/models/app-state/app_state.dart';
import 'package:codraw/models/domain-objects/domain_object.dart';
import 'package:codraw/widgets/drawing/drawing_canvas.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

class DrawingPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 50,
          child: Row(
            children: [
              TextButton(
                onPressed: () =>
                    context.dispatch(ClearClassBoxesAction()),
                child: Text('clear'),
              )
            ],
          ),
        ),
        Expanded(
          child: StoreConnector<AppState, IList<ClassBox>>(
              onInit: (store) => context.dispatch(
                  ConnectDataStreamAction(SyncSection.classBoxes)),
              distinct: true,
              converter: (store) => store.state.classBoxes,
              builder: (context, boxes) => DrawingCanvas(boxes.unlockView)),
        ),
      ],
    );
  }
}
