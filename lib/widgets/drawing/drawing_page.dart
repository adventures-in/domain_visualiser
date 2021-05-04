import 'package:domain_visualiser/actions/shared/connect_data_stream_action.dart';
import 'package:domain_visualiser/enums/database/database_section_enum.dart';
import 'package:domain_visualiser/extensions/flutter/context_extensions.dart';
import 'package:domain_visualiser/models/app-state/app_state.dart';
import 'package:domain_visualiser/models/domain-objects/domain_object.dart';
import 'package:domain_visualiser/widgets/drawing/drawing_canvas.dart';
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
            children: [TextButton(onPressed: () {}, child: Text('clear'))],
          ),
        ),
        Expanded(
          child: StoreConnector<AppState, IList<ClassBox>>(
              onInit: (store) => context.dispatch(
                  ConnectDataStreamAction(DatabaseSectionEnum.classBoxes)),
              distinct: true,
              converter: (store) => store.state.classBoxes,
              builder: (context, boxes) => DrawingCanvas(boxes.unlockView)),
        ),
      ],
    );
  }
}
