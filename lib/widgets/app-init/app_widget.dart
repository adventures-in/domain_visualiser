import 'package:domain_visualiser/actions/app-init/plumb_streams_action.dart';
import 'package:domain_visualiser/actions/auth/observe_auth_state_action.dart';
import 'package:domain_visualiser/actions/navigation/remove_current_page_action.dart';
import 'package:domain_visualiser/actions/platform/detect_platform_action.dart';
import 'package:domain_visualiser/extensions/page_data_extensions.dart';
import 'package:domain_visualiser/extensions/settings_extensions.dart';
import 'package:domain_visualiser/models/app-state/app_state.dart';
import 'package:domain_visualiser/models/navigation/page_data/page_data.dart';
import 'package:domain_visualiser/models/settings/settings.dart';
import 'package:domain_visualiser/services/wrappers/firebase_wrapper.dart';
import 'package:domain_visualiser/utils/redux_bundle.dart';
import 'package:domain_visualiser/widgets/app-init/initializing_error_page.dart';
import 'package:domain_visualiser/widgets/app-init/initializing_indicator.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

class AppWidget extends StatefulWidget {
  final FirebaseWrapper _firebase;
  final ReduxBundle? _redux;

  AppWidget({FirebaseWrapper? firebase, ReduxBundle? redux})
      : _firebase = firebase ?? FirebaseWrapper(),
        _redux = redux;

  @override
  _AppWidgetState createState() => _AppWidgetState();
}

class _AppWidgetState extends State<AppWidget> {
  late ReduxBundle _redux;
  late Store<AppState> _store;
  dynamic _error;
  bool _initializedFirebase = false;
  bool _initializedRedux = false;

  void initializeFlutterFire() async {
    try {
      // firebase must be initialised first so createStore() can run
      await widget._firebase.init();
      setState(() {
        _initializedFirebase = true;
      });

      // use the injected redux bundle if there is one or create one
      _redux = widget._redux ?? ReduxBundle();
      // create the redux store and run any extra operations
      _store = await _redux.createStore();
      setState(() {
        _initializedRedux = true;
      });

      /// This should happen once on app load, the various streams from the
      /// [FirebaseFirestore] database are changed but the [DatabaseService]'s
      /// [StreamController] stays connected to the redux [Store].
      _store.dispatch(PlumbStreamsAction());

      // dispatch initial actions
      _store.dispatch(ObserveAuthStateAction());
      _store.dispatch(DetectPlatformAction());
    } catch (e) {
      setState(() {
        _error = e;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    initializeFlutterFire();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return InitializingErrorPage(error: _error, trace: StackTrace.current);
    }

    // Show a loader until FlutterFire is initialized
    if (!_initializedFirebase || !_initializedRedux) {
      return InitializingIndicator(
        firebaseDone: _initializedFirebase,
        reduxDone: _initializedRedux,
      );
    }

    return StoreProvider<AppState>(
      store: _store,
      child: StoreConnector<AppState, Settings>(
        distinct: true,
        converter: (store) => store.state.settings,
        builder: (context, settings) {
          return MaterialApp(
            title: 'Visualise Your Domain',
            theme: MakeThemeData.from(settings.lightTheme),
            darkTheme: MakeThemeData.from(settings.darkTheme),
            themeMode: MakeThemeMode.from(settings.brightnessMode),
            home: StoreConnector<AppState, IList<PageData>>(
              distinct: true,
              converter: (store) => store.state.pagesData,
              builder: (context, pagesData) => Navigator(
                  pages: pagesData.toPages(),
                  onPopPage: (route, dynamic result) {
                    if (!route.didPop(result)) {
                      return false;
                    }

                    if (route.isCurrent) {
                      _store.dispatch(RemoveCurrentPageAction());
                    }

                    return true;
                  }),
            ),
          );
        },
      ),
    );
  }
}
