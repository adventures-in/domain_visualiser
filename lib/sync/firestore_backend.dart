import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:domain_visualiser/actions/domain-objects/store_class_boxes_action.dart';
import 'package:domain_visualiser/actions/redux_action.dart';
import 'package:domain_visualiser/enums/database/database_section_enum.dart';
import 'package:domain_visualiser/extensions/firebase/firestore_extensions.dart';
import 'package:domain_visualiser/extensions/redux/actions_stream_controller_extensions.dart';
import 'package:domain_visualiser/models/domain-objects/domain_object.dart';
import 'package:domain_visualiser/sync/graph_sync_backend.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

/// A [GraphSyncBackend] backed by Cloud Firestore.
///
/// Observes collections (converting [DocumentSnapshot]/[QuerySnapshot] into
/// [ReduxAction]s on [actionStream]) and persists local node changes.
class FirestoreBackend implements GraphSyncBackend {
  /// A map of DatabaseSectionEnum to database location
  static const locationOf = <DatabaseSectionEnum, String>{
    DatabaseSectionEnum.classBoxes: 'domain-objects',
    DatabaseSectionEnum.profile: 'profile'
  };

  /// The [FirebaseFirestore] instance
  final FirebaseFirestore _firestore;

  /// Keep track of the subscriptions so we can cancel them later.
  final Map<DatabaseSectionEnum, StreamSubscription> _subscriptions = {};

  /// The [_eventsController] is connected to the redux [Store] via [actionStream]
  /// and is used to add actions to the stream where they will be dispatched.
  final StreamController<ReduxAction> _eventsController;

  FirestoreBackend(
      {FirebaseFirestore? database,
      StreamController<ReduxAction>? eventsController})
      : _firestore = database ?? FirebaseFirestore.instance,
        _eventsController = eventsController ?? StreamController<ReduxAction>();

  /// Observe a collection at [locationOf] and convert the resultant
  /// [DocumentSnapshot]/[QuerySnapshot] into a [ReduxAction] to send to the store.
  @override
  void connect(DatabaseSectionEnum section) {
    try {
      // connect the database to the store and keep the subscription
      _subscriptions[section] = _firestore
          .collection(locationOf[section]!)
          .snapshots()
          .listen((QuerySnapshot snapshot) {
        try {
          final classBoxes =
              snapshot.docs.map((doc) => doc.toClassBox()).toIList();
          _eventsController.add(StoreClassBoxesAction(classBoxes));
        } catch (error, trace) {
          _eventsController.addProblem(error, trace);
        }
      }, onError: _eventsController.addProblem);
    } catch (error, trace) {
      _eventsController.addProblem(error, trace);
    }
  }

  @override
  void disconnect(DatabaseSectionEnum section) =>
      _subscriptions[section]?.cancel();

  @override
  Future<void> addNode(ClassBox node) async {
    try {
      await _firestore.doc('domain-objects/${node.id}').set(node.toJson());
    } catch (error, trace) {
      _eventsController.addProblem(error, trace);
    }
  }

  @override
  Future<void> updateNode(DomainObject node) async {
    try {
      await _firestore.doc('${_getPath(node)}/${node.id}').update(node.toJson());
    } catch (error, trace) {
      _eventsController.addProblem(error, trace);
    }
  }

  /// The stream is used once on app load to connect the [_eventsController] to
  /// the redux [Store]. Functions that observe parts of the database don't
  /// return anything — they connect the store to the database and keep the
  /// subscription, so callers that stop observing just cancel the subscription.
  @override
  Stream<ReduxAction> get actionStream => _eventsController.stream;

  String _getPath(DomainObject object) {
    return object.when<String>(
        classBox: (String? type,
                String id,
                int? flightTime,
                String? userId,
                double left,
                double top,
                double right,
                double bottom,
                String? name,
                IList<String>? staticMethods,
                IList<String>? instanceMethods,
                IList<String>? staticVariables,
                IList<String>? instanceVariables) =>
            'domain-objects');
  }
}
