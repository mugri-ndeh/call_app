part of 'call_cubit.dart';

enum CallStatus { initial, calling, ringing, inCall, error }

class CallState extends Equatable {
  final bool isLoading;
  final CallStatus status;
  final String? errorMessage;

  const CallState({
    this.isLoading = false,
    this.status = CallStatus.initial,
    this.errorMessage,
  });

  CallState copyWith({
    bool? isLoading,
    CallStatus? status,
    String? errorMessage,
  }) {
    return CallState(
      isLoading: isLoading ?? this.isLoading,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [isLoading, status, errorMessage];
}
