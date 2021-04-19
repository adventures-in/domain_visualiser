import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:domain_visualiser/models/class_box.dart';
import 'package:domain_visualiser/models/profile/profile_data.dart';
import 'package:flutter/painting.dart';

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
        Rect.fromLTRB(data()['left'] as double, data()['top'] as double,
            data()['right'] as double, data()['bottom'] as double),
      );
}
