import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

part 'messages_state.dart';

class MessagesCubit extends Cubit<MessagesState> {
  MessagesCubit() : super(MessagesInitial());
}
