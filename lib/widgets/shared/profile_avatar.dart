import 'package:domain_visualiser/actions/navigation/push_page_action.dart';
import 'package:domain_visualiser/extensions/flutter/context_extensions.dart';
import 'package:domain_visualiser/models/navigation/page_data/page_data.dart';
import 'package:domain_visualiser/widgets/shared/checked_circle_avatar.dart';
import 'package:flutter/material.dart';

class ProfileAvatar extends StatelessWidget {
  final String? photoURL;
  const ProfileAvatar(this.photoURL, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final localPhotoURL = photoURL; // gimme that flow analysis
    return RawMaterialButton(
      onPressed: () =>
          context.dispatch(PushPageAction(data: ProfilePageData())),
      elevation: 0.0,
      fillColor: Colors.white,
      padding: EdgeInsets.all(5.0),
      shape: CircleBorder(),
      child: CircleAvatar(
        radius: 17,
        backgroundColor: Color(0xffFDCF09),
        child: (localPhotoURL == null)
            ? Icon(Icons.account_circle_outlined)
            : CheckedCircleAvatar(radius: 15, url: localPhotoURL),
      ),
    );
  }
}
