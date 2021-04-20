import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:domain_visualiser/models/domain-objects/class_box.dart';
import 'package:domain_visualiser/models/profile/profile_data.dart';

extension ConvertDocumentSnapshot on DocumentSnapshot {
  ProfileData toProfileData() {
    if (!exists) {
      throw 'snapshot indicated data does not exist';
    }

    return ProfileData(
        id: id,
        displayName: data()?['displayName'] as String,
        photoURL: data()?['photoURL'] as String? ??
            'https://www.gravatar.com/avatar/00000000000000000000000000000000?d=mp&f=y',
        firstName: data()?['firstName'] as String? ?? '_',
        lastName: data()?['lastName'] as String? ?? '_');
  }
}

extension ConvertQueryDocumentSnapshot on QueryDocumentSnapshot {
  ClassBox toClassBox() => ClassBox(
      id: id,
      left: data()['left'] as double,
      top: data()['top'] as double,
      right: data()['right'] as double,
      bottom: data()['bottom'] as double,
      name: data()['name'] as String);
}
