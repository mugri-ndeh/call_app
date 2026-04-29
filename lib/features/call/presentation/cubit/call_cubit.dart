import 'package:call_app/utils/signalling/signalling_utils.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

part 'call_state.dart';

@injectable
class CallCubit extends Cubit<CallState> {
  CallCubit(this.signallingService) : super(const CallState());

  final SignallingService signallingService;
}
