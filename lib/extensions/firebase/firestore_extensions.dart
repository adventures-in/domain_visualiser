import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:codraw/actions/profile/store_profile_action.dart';
import 'package:codraw/actions/redux_action.dart';
import 'package:codraw/sync/sync_section.dart';
import 'package:codraw/models/domain-objects/domain_object.dart';
import 'package:codraw/models/profile/profile_data.dart';

extension ConvertDocumentSnapshot on DocumentSnapshot {
  ProfileData toProfileData() {
    if (!exists) {
      throw 'snapshot indicated data does not exist';
    }

    return ProfileData(
        id: id,
        displayName: (data() as Map<String, dynamic>?)?['displayName'] as String,
        photoURL: (data() as Map<String, dynamic>?)?['photoURL'] as String? ??
            'https://www.gravatar.com/avatar/00000000000000000000000000000000?d=mp&f=y',
        firstName: (data() as Map<String, dynamic>?)?['firstName'] as String? ?? '_',
        lastName: (data() as Map<String, dynamic>?)?['lastName'] as String? ?? '_');
  }

  ClassBox toClassBox() => ClassBox(
      id: id,
      left: (data()! as Map<String, dynamic>)['left'] as double,
      top: (data()! as Map<String, dynamic>)['top'] as double,
      right: (data()! as Map<String, dynamic>)['right'] as double,
      bottom: (data()! as Map<String, dynamic>)['bottom'] as double,
      name: (data() as Map<String, dynamic>?)?['name'] as String?);

  ReduxAction toStoreAction(SyncSection section) {
    switch (section) {
      case SyncSection.classBoxes:
      // return StoreClassBoxesAction(data());
      case SyncSection.profile:
        return StoreProfileAction(toProfileData());
    }
  }
}

// extension ConvertQueryDocumentSnapshot on QueryDocumentSnapshot {
//   ClassBox toClassBox() => ClassBox(
//       id: id,
//       left: data()['left'] as double,
//       top: data()['top'] as double,
//       right: data()['right'] as double,
//       bottom: data()['bottom'] as double,
//       name: data()['name'] as String);
// }
