import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'dart:io';
import '../../services/excel_service.dart';
import '../../data/models/rider_model.dart';
import '../../data/repositories/rider_repository.dart';
import 'dart:async';
import '../../utils/user_friendly_error.dart';

// --- Events ---
abstract class RidersEvent extends Equatable {
  const RidersEvent();

  @override
  List<Object?> get props => [];
}

class LoadRiders extends RidersEvent {}

class AddRider extends RidersEvent {
  final RiderModel rider;
  const AddRider(this.rider);

  @override
  List<Object> get props => [rider];
}

class UpdateRider extends RidersEvent {
  final RiderModel rider;
  const UpdateRider(this.rider);

  @override
  List<Object> get props => [rider];
}

class SearchRiders extends RidersEvent {
  final String query;
  const SearchRiders(this.query);

  @override
  List<Object> get props => [query];
}

class FilterRiders extends RidersEvent {
  final String? city;
  final RiderStatus? status;
  final bool clearCity;
  final bool clearStatus;

  const FilterRiders({
    this.city,
    this.status,
    this.clearCity = false,
    this.clearStatus = false,
  });

  @override
  List<Object?> get props => [city, status, clearCity, clearStatus];
}

class UploadRiders extends RidersEvent {
  final File file;
  const UploadRiders(this.file);

  @override
  List<Object> get props => [file];
}

class RidersStreamUpdated extends RidersEvent {
  final List<RiderModel> riders;
  const RidersStreamUpdated(this.riders);

  @override
  List<Object?> get props => [riders];
}

// --- States ---
abstract class RidersState extends Equatable {
  const RidersState();

  @override
  List<Object?> get props => [];
}

class RidersLoading extends RidersState {}

class RidersLoaded extends RidersState {
  final List<RiderModel> riders;
  final List<RiderModel> allRiders;

  final String searchQuery;
  final String? filterCity;
  final RiderStatus? filterStatus;

  final bool isUploadSuccess;
  final String? uploadMessage;
  final List<String> uploadLogs;

  const RidersLoaded(
    this.riders, {
    required this.allRiders,
    this.searchQuery = '',
    this.filterCity,
    this.filterStatus,
    this.isUploadSuccess = false,
    this.uploadMessage,
    this.uploadLogs = const [],
  });

  RidersLoaded copyWith({
    List<RiderModel>? riders,
    List<RiderModel>? allRiders,
    String? searchQuery,
    String? filterCity,
    RiderStatus? filterStatus,
    bool clearCity = false,
    bool clearStatus = false,
    bool? isUploadSuccess,
    String? uploadMessage,
    List<String>? uploadLogs,
  }) {
    return RidersLoaded(
      riders ?? this.riders,
      allRiders: allRiders ?? this.allRiders,
      searchQuery: searchQuery ?? this.searchQuery,
      filterCity: clearCity ? null : (filterCity ?? this.filterCity),
      filterStatus: clearStatus ? null : (filterStatus ?? this.filterStatus),
      isUploadSuccess: isUploadSuccess ?? this.isUploadSuccess,
      uploadMessage: uploadMessage ?? this.uploadMessage,
      uploadLogs: uploadLogs ?? this.uploadLogs,
    );
  }

  @override
  List<Object?> get props => [
    riders,
    allRiders,
    searchQuery,
    filterCity,
    filterStatus,
    isUploadSuccess,
    uploadMessage,
    uploadLogs,
  ];
}

class RidersError extends RidersState {
  final String message;
  const RidersError(this.message);

  @override
  List<Object> get props => [message];
}

// --- Bloc ---
class RidersBloc extends Bloc<RidersEvent, RidersState> {
  final RiderRepository _repository;
  StreamSubscription<List<RiderModel>>? _ridersSub;

  bool _isUploading = false;

  RidersBloc(this._repository) : super(RidersLoading()) {
    on<LoadRiders>(_onLoadRiders);
    on<AddRider>(_onAddRider);
    on<UpdateRider>(_onUpdateRider);
    on<SearchRiders>(_onSearchRiders);
    on<FilterRiders>(_onFilterRiders);
    on<UploadRiders>(_onUploadRiders);
    on<RidersStreamUpdated>(_onRidersStreamUpdated);

    _ridersSub = _repository.getRidersStream().listen(
      (list) {
        // Block stream updates while upload flow is reconciling state.
        if (_isUploading) return;
        add(RidersStreamUpdated(list));
      },
      onError: (error) {
        print('Error in RidersBloc rider stream: $error');
      },
      cancelOnError: false,
    );
  }

  @override
  Future<void> close() {
    _ridersSub?.cancel();
    return super.close();
  }

  void _applyFilters(Emitter<RidersState> emit, RidersLoaded state) {
    List<RiderModel> filtered = state.allRiders;

    if (state.searchQuery.isNotEmpty) {
      final q = state.searchQuery.toLowerCase();
      filtered = filtered.where((r) {
        return r.name.toLowerCase().contains(q) ||
            r.id.toLowerCase().contains(q) ||
            (r.passportNumber?.toLowerCase().contains(q) ?? false);
      }).toList();
    }

    if (state.filterCity != null) {
      filtered = filtered
          .where(
            (r) => r.city?.toLowerCase() == state.filterCity!.toLowerCase(),
          )
          .toList();
    }

    if (state.filterStatus != null) {
      filtered = filtered.where((r) => r.status == state.filterStatus).toList();
    }

    emit(state.copyWith(riders: filtered));
  }

  Future<void> _onUploadRiders(
    UploadRiders event,
    Emitter<RidersState> emit,
  ) async {
    final RidersLoaded? previousLoadedState = state is RidersLoaded
        ? state as RidersLoaded
        : null;

    _isUploading = true;
    emit(RidersLoading());

    try {
      final result = await ExcelService.instance.parseFile(event.file);
      final riders = previousLoadedState?.allRiders ?? <RiderModel>[];

      String message = "Upload completed.";
      List<String> logs = [];
      bool uploadSuccess = false;
      if (result is Map<String, dynamic>) {
        final success = (result['success'] as num?)?.toInt() ?? 0;
        final failed = result['failed'] ?? 0;
        final serverMessage = result['message']?.toString();
        message = (serverMessage != null && serverMessage.isNotEmpty)
            ? serverMessage
            : "Success: $success, Failed: $failed";
        logs = (result['logs'] as List?)?.cast<String>() ?? [];
        uploadSuccess = success > 0;
      } else {
        message = "No rider records were detected in this file.";
      }

      emit(RidersLoaded(
        riders,
        allRiders: riders,
        isUploadSuccess: uploadSuccess,
        uploadMessage: message,
        uploadLogs: logs,
      ));

      // Refresh rider list in background so UI feedback is immediate.
      add(LoadRiders());
    } catch (e) {
      emit(RidersError(toUserFriendlyErrorMessage(e, fallback: 'Failed to upload riders.')));
    } finally {
      _isUploading = false;
    }
  }

  Future<void> _onLoadRiders(
    LoadRiders event,
    Emitter<RidersState> emit,
  ) async {
    try {
      final riders = await _repository.fetchRiders();
      emit(RidersLoaded(riders, allRiders: riders));
    } catch (e) {
      emit(RidersError(toUserFriendlyErrorMessage(e, fallback: 'Failed to load riders.')));
    }
  }

  Future<void> _onAddRider(AddRider event, Emitter<RidersState> emit) async {
    final currentState = state;

    if (currentState is RidersLoaded) {
      try {
        await _repository.addRider(event.rider);

        final updatedList = List<RiderModel>.from(currentState.allRiders)
          ..add(event.rider);

        final newState = currentState.copyWith(allRiders: updatedList);

        _applyFilters(emit, newState);
      } catch (e) {
        emit(RidersError(toUserFriendlyErrorMessage(e, fallback: 'Failed to add rider.')));
      }
    }
  }

  Future<void> _onUpdateRider(
    UpdateRider event,
    Emitter<RidersState> emit,
  ) async {
    final currentState = state;

    if (currentState is RidersLoaded) {
      try {
        await _repository.updateRider(event.rider);

        final updatedList = currentState.allRiders.map((r) {
          return r.id == event.rider.id ? event.rider : r;
        }).toList();

        final newState = currentState.copyWith(allRiders: updatedList);

        _applyFilters(emit, newState);
      } catch (e) {
        emit(RidersError(toUserFriendlyErrorMessage(e, fallback: 'Failed to update rider.')));
      }
    }
  }

  void _onSearchRiders(SearchRiders event, Emitter<RidersState> emit) {
    final currentState = state;

    if (currentState is RidersLoaded) {
      final newState = currentState.copyWith(searchQuery: event.query);

      _applyFilters(emit, newState);
    }
  }

  void _onFilterRiders(FilterRiders event, Emitter<RidersState> emit) {
    final currentState = state;

    if (currentState is RidersLoaded) {
      final newState = currentState.copyWith(
        filterCity: event.city,
        clearCity: event.clearCity,
        filterStatus: event.status,
        clearStatus: event.clearStatus,
      );

      _applyFilters(emit, newState);
    }
  }

  Future<void> _onRidersStreamUpdated(
    RidersStreamUpdated event,
    Emitter<RidersState> emit,
  ) async {
    // 🔥 FIX: Ignore stream during upload
    if (_isUploading) return;

    final riders = event.riders;
    final currentState = state;

    if (currentState is RidersLoaded) {
      final newState = currentState.copyWith(allRiders: riders);

      _applyFilters(emit, newState);
    } else {
      emit(RidersLoaded(riders, allRiders: riders));
    }
  }
}
