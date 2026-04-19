import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/models/journal_template_model.dart';
import '../../data/repositories/journal_template_repository.dart';
import '../../utils/user_friendly_error.dart';

// Events
abstract class JournalTemplateEvent extends Equatable {
  const JournalTemplateEvent();
  @override
  List<Object?> get props => [];
}

class LoadTemplates extends JournalTemplateEvent {}

class CreateTemplate extends JournalTemplateEvent {
  final JournalTemplateModel template;
  const CreateTemplate(this.template);
  @override
  List<Object> get props => [template];
}

class DeleteTemplate extends JournalTemplateEvent {
  final String id;
  const DeleteTemplate(this.id);
  @override
  List<Object> get props => [id];
}

// States
abstract class JournalTemplateState extends Equatable {
  const JournalTemplateState();
  @override
  List<Object?> get props => [];
}

class JournalTemplateInitial extends JournalTemplateState {}

class JournalTemplateLoading extends JournalTemplateState {}

class JournalTemplateLoaded extends JournalTemplateState {
  final List<JournalTemplateModel> templates;
  const JournalTemplateLoaded(this.templates);
  @override
  List<Object> get props => [templates];
}

class JournalTemplateError extends JournalTemplateState {
  final String message;
  const JournalTemplateError(this.message);
  @override
  List<Object> get props => [message];
}

// Bloc
class JournalTemplateBloc
    extends Bloc<JournalTemplateEvent, JournalTemplateState> {
  final JournalTemplateRepository _repository;

  JournalTemplateBloc(this._repository) : super(JournalTemplateInitial()) {
    on<LoadTemplates>(_onLoadTemplates);
    on<CreateTemplate>(_onCreateTemplate);
    on<DeleteTemplate>(_onDeleteTemplate);
  }

  Future<void> _onLoadTemplates(
    LoadTemplates event,
    Emitter<JournalTemplateState> emit,
  ) async {
    emit(JournalTemplateLoading());
    try {
      final templates = await _repository.fetchTemplates();
      emit(JournalTemplateLoaded(templates));
    } catch (e) {
      emit(JournalTemplateError(toUserFriendlyError(e)));
    }
  }

  Future<void> _onCreateTemplate(
    CreateTemplate event,
    Emitter<JournalTemplateState> emit,
  ) async {
    try {
      await _repository.createTemplate(event.template);
      add(LoadTemplates());
    } catch (e) {
      emit(JournalTemplateError(toUserFriendlyError(e)));
    }
  }

  Future<void> _onDeleteTemplate(
    DeleteTemplate event,
    Emitter<JournalTemplateState> emit,
  ) async {
    try {
      await _repository.deleteTemplate(event.id);
      add(LoadTemplates());
    } catch (e) {
      emit(JournalTemplateError(toUserFriendlyError(e)));
    }
  }
}
