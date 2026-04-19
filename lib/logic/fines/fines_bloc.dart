import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/models/fines_model.dart';
import '../../data/models/rider_model.dart'; // Added
import '../../data/repositories/fines_repository.dart';
import 'dart:io';
import 'dart:async';
import '../../services/excel_service.dart';
import '../../data/repositories/rider_repository.dart';
import '../../utils/user_friendly_error.dart';

// Events
abstract class FinesEvent extends Equatable {
  const FinesEvent();
  @override
  List<Object?> get props => [];
}

class LoadFines extends FinesEvent {}

class SearchFines extends FinesEvent {
  final String query;
  const SearchFines(this.query);
  @override
  List<Object> get props => [query];
}

class FilterFines extends FinesEvent {
  final FineStatus? status;
  final int? month; // 1-12
  final bool? highAmount; // > 500
  final bool clearStatus;
  final bool clearMonth;
  final bool clearAmount;

  const FilterFines({
    this.status,
    this.month,
    this.highAmount,
    this.clearStatus = false,
    this.clearMonth = false,
    this.clearAmount = false,
  });

  @override
  List<Object?> get props => [
    status,
    month,
    highAmount,
    clearStatus,
    clearMonth,
    clearAmount,
  ];
}

class UploadFinesSheet extends FinesEvent {
  final dynamic file;
  const UploadFinesSheet(this.file);
  @override
  List<Object> get props => [file];
}

class UploadSalikSheet extends FinesEvent {
  final dynamic file;
  const UploadSalikSheet(this.file);
  @override
  List<Object> get props => [file];
}

class EditFineAmount extends FinesEvent {
  final String fineId;
  final double newAmount;

  const EditFineAmount(this.fineId, this.newAmount);

  @override
  List<Object> get props => [fineId, newAmount];
}

class ManualAssignFine extends FinesEvent {
  final String fineId;
  final String riderId;
  const ManualAssignFine({required this.fineId, required this.riderId});
  @override
  List<Object> get props => [fineId, riderId];
}

class BulkUpdateFineStatus extends FinesEvent {
  final List<String> fineIds;
  final String status;
  const BulkUpdateFineStatus({required this.fineIds, required this.status});
  @override
  List<Object> get props => [fineIds, status];
}

class FetchAssignmentProof extends FinesEvent {
  final String fineId;
  const FetchAssignmentProof(this.fineId);
  @override
  List<Object> get props => [fineId];
}

class ToggleFineSelection extends FinesEvent {
  final String fineId;
  const ToggleFineSelection(this.fineId);
  @override
  List<Object> get props => [fineId];
}

class ClearSelection extends FinesEvent {}

class AutoMatchFines extends FinesEvent {
  final List<String> fineIds;
  const AutoMatchFines(this.fineIds);
  @override
  List<Object> get props => [fineIds];
}

class ConfirmPartialMatch extends FinesEvent {
  final String fineId;
  const ConfirmPartialMatch(this.fineId);
  @override
  List<Object> get props => [fineId];
}

class UnlinkRider extends FinesEvent {
  final String fineId;
  const UnlinkRider(this.fineId);
  @override
  List<Object> get props => [fineId];
}

class PaySelectedFines extends FinesEvent {
  final List<String> fineIds;
  final String drawerId;
  const PaySelectedFines(this.fineIds, this.drawerId);
  @override
  List<Object> get props => [fineIds, drawerId];
}

class LoadBikeData extends FinesEvent {}

// States
abstract class FinesState extends Equatable {
  final List<FineModel> fines; // Displayed fines
  final List<FineModel> allFines; // Source of truth
  final List<BikeModel> bikes;
  final List<BikeAssignmentModel> assignments;
  final List<RiderModel> riders;

  // Filter State
  final String searchQuery;
  final FineStatus? filterStatus;
  final int? filterMonth;
  final bool? filterHighAmount;

  // Selection & Proof
  final Set<String> selectedIds;
  final Map<String, dynamic>? assignmentProof;
  final bool isProofLoading;
  final bool isProcessing;
  final String? uploadMessage; // Added
  final List<String> uploadLogs; // Added

  const FinesState({
    this.fines = const [],
    this.allFines = const [],
    this.bikes = const [],
    this.assignments = const [],
    this.riders = const [],
    this.searchQuery = '',
    this.filterStatus,
    this.filterMonth,
    this.filterHighAmount,
    this.selectedIds = const {},
    this.assignmentProof,
    this.isProofLoading = false,
    this.isProcessing = false,
    this.uploadMessage,
    this.uploadLogs = const [],
  });

  FinesState copyWith({
    List<FineModel>? fines,
    List<FineModel>? allFines,
    List<BikeModel>? bikes,
    List<BikeAssignmentModel>? assignments,
    List<RiderModel>? riders,
    String? searchQuery,
    FineStatus? filterStatus,
    int? filterMonth,
    bool? filterHighAmount,
    bool clearStatus = false,
    bool clearMonth = false,
    bool clearAmount = false,
    Set<String>? selectedIds,
    Map<String, dynamic>? assignmentProof,
    bool clearProof = false,
    bool? isProofLoading,
    bool? isProcessing,
    String? uploadMessage,
    List<String>? uploadLogs,
  });

  @override
  List<Object?> get props => [
    fines,
    allFines,
    bikes,
    assignments,
    riders,
    searchQuery,
    filterStatus,
    filterMonth,
    filterHighAmount,
    selectedIds,
    assignmentProof,
    isProofLoading,
    isProcessing,
    uploadMessage,
    uploadLogs,
  ];
}

class FinesInitial extends FinesState {
  @override
  FinesState copyWith({
    List<FineModel>? fines,
    List<FineModel>? allFines,
    List<BikeModel>? bikes,
    List<BikeAssignmentModel>? assignments,
    List<RiderModel>? riders,
    String? searchQuery,
    FineStatus? filterStatus,
    int? filterMonth,
    bool? filterHighAmount,
    bool clearStatus = false,
    bool clearMonth = false,
    bool clearAmount = false,
    Set<String>? selectedIds,
    Map<String, dynamic>? assignmentProof,
    bool clearProof = false,
    bool? isProofLoading,
    bool? isProcessing,
    String? uploadMessage,
    List<String>? uploadLogs,
  }) {
    return FinesInitial();
  }
}

class FinesLoading extends FinesState {
  const FinesLoading({
    super.fines,
    super.allFines,
    super.bikes,
    super.assignments,
    super.riders,
    super.searchQuery,
    super.filterStatus,
    super.filterMonth,
    super.filterHighAmount,
    super.selectedIds,
    super.assignmentProof,
    super.isProofLoading,
    super.isProcessing,
    super.uploadMessage,
    super.uploadLogs,
  });

  @override
  FinesLoading copyWith({
    List<FineModel>? fines,
    List<FineModel>? allFines,
    List<BikeModel>? bikes,
    List<BikeAssignmentModel>? assignments,
    List<RiderModel>? riders,
    String? searchQuery,
    FineStatus? filterStatus,
    int? filterMonth,
    bool? filterHighAmount,
    bool clearStatus = false,
    bool clearMonth = false,
    bool clearAmount = false,
    Set<String>? selectedIds,
    Map<String, dynamic>? assignmentProof,
    bool clearProof = false,
    bool? isProofLoading,
    bool? isProcessing,
    String? uploadMessage,
    List<String>? uploadLogs,
  }) {
    return FinesLoading(
      fines: fines ?? this.fines,
      allFines: allFines ?? this.allFines,
      bikes: bikes ?? this.bikes,
      assignments: assignments ?? this.assignments,
      riders: riders ?? this.riders,
      searchQuery: searchQuery ?? this.searchQuery,
      filterStatus: clearStatus ? null : (filterStatus ?? this.filterStatus),
      filterMonth: clearMonth ? null : (filterMonth ?? this.filterMonth),
      filterHighAmount: clearAmount
          ? null
          : (filterHighAmount ?? this.filterHighAmount),
      selectedIds: selectedIds ?? this.selectedIds,
      assignmentProof: clearProof
          ? null
          : (assignmentProof ?? this.assignmentProof),
      isProofLoading: isProofLoading ?? this.isProofLoading,
      isProcessing: isProcessing ?? this.isProcessing,
      uploadMessage: uploadMessage ?? this.uploadMessage,
      uploadLogs: uploadLogs ?? this.uploadLogs,
    );
  }
}

class FinesLoaded extends FinesState {
  const FinesLoaded({
    required super.fines,
    required super.allFines, // Required source
    super.bikes,
    super.assignments,
    super.riders,
    super.searchQuery,
    super.filterStatus,
    super.filterMonth,
    super.filterHighAmount,
    super.selectedIds,
    super.assignmentProof,
    super.isProofLoading,
    super.isProcessing,
    super.uploadMessage,
    super.uploadLogs,
  });

  @override
  FinesLoaded copyWith({
    List<FineModel>? fines,
    List<FineModel>? allFines,
    List<BikeModel>? bikes,
    List<BikeAssignmentModel>? assignments,
    List<RiderModel>? riders,
    String? searchQuery,
    FineStatus? filterStatus,
    int? filterMonth,
    bool? filterHighAmount,
    bool clearStatus = false,
    bool clearMonth = false,
    bool clearAmount = false,
    Set<String>? selectedIds,
    Map<String, dynamic>? assignmentProof,
    bool clearProof = false,
    bool? isProofLoading,
    bool? isProcessing,
    String? uploadMessage,
    List<String>? uploadLogs,
  }) {
    return FinesLoaded(
      fines: fines ?? this.fines,
      allFines: allFines ?? this.allFines,
      bikes: bikes ?? this.bikes,
      assignments: assignments ?? this.assignments,
      riders: riders ?? this.riders,
      searchQuery: searchQuery ?? this.searchQuery,
      filterStatus: clearStatus ? null : (filterStatus ?? this.filterStatus),
      filterMonth: clearMonth ? null : (filterMonth ?? this.filterMonth),
      filterHighAmount: clearAmount
          ? null
          : (filterHighAmount ?? this.filterHighAmount),
      selectedIds: selectedIds ?? this.selectedIds,
      assignmentProof: clearProof
          ? null
          : (assignmentProof ?? this.assignmentProof),
      isProofLoading: isProofLoading ?? this.isProofLoading,
      isProcessing: isProcessing ?? this.isProcessing,
      uploadMessage: uploadMessage ?? this.uploadMessage,
      uploadLogs: uploadLogs ?? this.uploadLogs,
    );
  }
}

class FinesError extends FinesState {
  final String message;
  const FinesError(
    this.message, {
    super.fines,
    super.allFines,
    super.bikes,
    super.assignments,
    super.riders,
    super.searchQuery,
    super.filterStatus,
    super.filterMonth,
    super.filterHighAmount,
    super.selectedIds,
    super.assignmentProof,
    super.isProofLoading,
    super.isProcessing,
    super.uploadMessage,
    super.uploadLogs,
  });

  @override
  FinesError copyWith({
    List<FineModel>? fines,
    List<FineModel>? allFines,
    List<BikeModel>? bikes,
    List<BikeAssignmentModel>? assignments,
    List<RiderModel>? riders,
    String? searchQuery,
    FineStatus? filterStatus,
    int? filterMonth,
    bool? filterHighAmount,
    bool clearStatus = false,
    bool clearMonth = false,
    bool clearAmount = false,
    Set<String>? selectedIds,
    Map<String, dynamic>? assignmentProof,
    bool clearProof = false,
    bool? isProofLoading,
    bool? isProcessing,
    String? uploadMessage,
    List<String>? uploadLogs,
  }) {
    return FinesError(
      message,
      fines: fines ?? this.fines,
      allFines: allFines ?? this.allFines,
      bikes: bikes ?? this.bikes,
      assignments: assignments ?? this.assignments,
      riders: riders ?? this.riders,
      searchQuery: searchQuery ?? this.searchQuery,
      filterStatus: clearStatus ? null : (filterStatus ?? this.filterStatus),
      filterMonth: clearMonth ? null : (filterMonth ?? this.filterMonth),
      filterHighAmount: clearAmount
          ? null
          : (filterHighAmount ?? this.filterHighAmount),
      selectedIds: selectedIds ?? this.selectedIds,
      assignmentProof: clearProof
          ? null
          : (assignmentProof ?? this.assignmentProof),
      isProofLoading: isProofLoading ?? this.isProofLoading,
      isProcessing: isProcessing ?? this.isProcessing,
      uploadMessage: uploadMessage ?? this.uploadMessage,
      uploadLogs: uploadLogs ?? this.uploadLogs,
    );
  }

  @override
  List<Object?> get props => [
    message,
    fines,
    allFines,
    bikes,
    assignments,
    searchQuery,
    filterStatus,
    filterMonth,
    filterHighAmount,
    isProcessing,
  ];
}

// Bloc

// Event to handle riders update
class UpdateRidersList extends FinesEvent {
  final List<RiderModel> riders;
  const UpdateRidersList(this.riders);
  @override
  List<Object> get props => [riders];
}

class FinesBloc extends Bloc<FinesEvent, FinesState> {
  final FinesRepository _repository;
  final RiderRepository _riderRepository;
  StreamSubscription<List<RiderModel>>? _ridersSub;

  FinesBloc(this._repository, this._riderRepository) : super(FinesInitial()) {
    on<LoadFines>(_onLoadFines);
    on<SearchFines>(_onSearchFines);
    on<FilterFines>(_onFilterFines);
    on<UploadFinesSheet>(_onUploadFinesSheet);
    on<UploadSalikSheet>(_onUploadSalikSheet);
    on<LoadBikeData>(_onLoadBikeData);
    on<ManualAssignFine>(_onManualAssignFine);
    on<EditFineAmount>(_onEditFineAmount);
    on<UpdateRidersList>(_onUpdateRidersList);
    on<BulkUpdateFineStatus>(_onBulkUpdateFineStatus);
    on<FetchAssignmentProof>(_onFetchAssignmentProof);
    on<ToggleFineSelection>(_onToggleFineSelection);
    on<ClearSelection>(_onClearSelection);
    on<AutoMatchFines>(_onAutoMatchFines);
    on<ConfirmPartialMatch>(_onConfirmPartialMatch);
    on<UnlinkRider>(_onUnlinkRider);
    on<PaySelectedFines>(_onPaySelectedFines);

    // Subscribe to riders stream
    _ridersSub = _riderRepository.getRidersStream().listen(
      (riders) {
        add(UpdateRidersList(riders));
      },
      onError: (error) {
        print("Error in FinesBloc rider stream: $error");
        // Optionally add an event to show error
      },
      cancelOnError: false,
    );
  }

  @override
  Future<void> close() {
    _ridersSub?.cancel();
    return super.close();
  }

  void _onUpdateRidersList(UpdateRidersList event, Emitter<FinesState> emit) {
    emit(state.copyWith(riders: event.riders));
    // Re-apply filters to potentially update names if needed?
    // _applyFilters(emit, state.copyWith(riders: event.riders));
  }

  void _applyFilters(Emitter<FinesState> emit, FinesState currentState) {
    List<FineModel> filtered = currentState.allFines;

    // 1. Search (Ticket or Plate or Rider Name)
    if (currentState.searchQuery.isNotEmpty) {
      final q = currentState.searchQuery.toLowerCase();
      filtered = filtered.where((f) {
        // Look up rider name if riderId exists
        String riderName = '';
        if (f.riderId != null && f.riderId!.isNotEmpty) {
          try {
            final rider = currentState.riders.firstWhere(
              (r) => r.id == f.riderId,
            );
            riderName = rider.name.toLowerCase();
          } catch (_) {}
        }

        return f.ticketNumber.toLowerCase().contains(q) ||
            f.plateNumber.toLowerCase().contains(q) ||
            riderName.contains(q);
      }).toList();
    }

    // 2. Status
    if (currentState.filterStatus != null) {
      filtered = filtered
          .where((f) => f.status == currentState.filterStatus)
          .toList();
    }

    // 3. Month
    if (currentState.filterMonth != null) {
      filtered = filtered
          .where((f) => f.violationDate.month == currentState.filterMonth)
          .toList();
    }

    // 4. High Amount (> 500)
    if (currentState.filterHighAmount == true) {
      filtered = filtered.where((f) => f.amount > 500).toList();
    }

    emit(currentState.copyWith(fines: filtered));
  }

  Future<void> _onLoadFines(LoadFines event, Emitter<FinesState> emit) async {
    emit(
      FinesLoading(
        fines: state.fines,
        allFines: state.allFines,
        bikes: state.bikes,
        assignments: state.assignments,
        riders: state.riders,
        searchQuery: state.searchQuery,
        filterStatus: state.filterStatus,
        filterMonth: state.filterMonth,
        filterHighAmount: state.filterHighAmount,
        selectedIds: state.selectedIds,
      ),
    );
    try {
      final fines = await _repository.fetchFines();
      // Ensure we have current assignments and riders for matching context
      final assignments = await _repository.fetchAssignments();
      final riders = await _riderRepository.fetchRiders();
      
      final newState = FinesLoaded(
        fines: fines, // Will be filtered next line
        allFines: fines,
        bikes: state.bikes,
        assignments: assignments,
        riders: riders,
        searchQuery: state.searchQuery,
        filterStatus: state.filterStatus,
        filterMonth: state.filterMonth,
        filterHighAmount: state.filterHighAmount,
        selectedIds: state.selectedIds,
      );
      _applyFilters(emit, newState);
    } catch (e) {
      emit(
        FinesError(
          toUserFriendlyError(e),
          fines: state.fines,
          allFines: state.allFines,
          bikes: state.bikes,
          assignments: state.assignments,
          riders: state.riders,
        ),
      );
    }
  }

  Future<void> _onLoadBikeData(
    LoadBikeData event,
    Emitter<FinesState> emit,
  ) async {
    try {
      final bikes = await _repository.fetchBikes();
      final assignments = await _repository.fetchAssignments();
      emit(state.copyWith(bikes: bikes, assignments: assignments));
    } catch (e) {
      print("Error loading bike data: $e");
    }
  }

  Future<void> _onUploadFinesSheet(
    UploadFinesSheet event,
    Emitter<FinesState> emit,
  ) async {
    emit(state.copyWith(isProcessing: true));
    try {
      File fileToParse;
      if (event.file is File) {
        fileToParse = event.file;
      } else {
        fileToParse = File(event.file.toString());
      }
      final result = await ExcelService.instance.parseFile(fileToParse);
      String? message;
      List<String> logs = [];

      if (result is Map<String, dynamic>) {
        final success = result['success'] ?? 0;
        final failed = result['failed'] ?? 0;
        message = "Success: $success, Failed: $failed";
        logs = (result['logs'] as List?)?.cast<String>() ?? [];
        
        if (success == 0 && failed > 0) {
           emit(FinesError("Sheet identified but no rows could be parsed. Check logs.", 
             fines: state.fines, allFines: state.allFines, uploadLogs: logs));
           return;
        }
      }
      
      add(LoadFines());
      emit(state.copyWith(uploadMessage: message, uploadLogs: logs));
    } catch (e) {
      emit(
        FinesError(
          toUserFriendlyErrorMessage(e, fallback: 'Failed to process fines sheet.'),
          fines: state.fines,
          allFines: state.allFines,
        ),
      );
    } finally {
      emit(state.copyWith(isProcessing: false));
    }
  }

  Future<void> _onUploadSalikSheet(
    UploadSalikSheet event,
    Emitter<FinesState> emit,
  ) async {
    emit(state.copyWith(isProcessing: true));
    try {
      File fileToParse;
      if (event.file is File) {
        fileToParse = event.file;
      } else {
        fileToParse = File(event.file.toString());
      }
      final result = await ExcelService.instance.parseSalikSheet(fileToParse);
      String? message;
      List<String> logs = [];

      final success = result['success'] ?? 0;
      final failed = result['failed'] ?? 0;
      message = "Salik Success: $success, Failed: $failed";
      logs = (result['logs'] as List?)?.cast<String>() ?? [];

      add(LoadFines());
      emit(state.copyWith(uploadMessage: message, uploadLogs: logs));
    } catch (e) {
      emit(
        FinesError(
          toUserFriendlyErrorMessage(e, fallback: 'Failed to process salik sheet.'),
          fines: state.fines,
          allFines: state.allFines,
        ),
      );
    } finally {
      emit(state.copyWith(isProcessing: false));
    }
  }

  Future<void> _onEditFineAmount(
    EditFineAmount event,
    Emitter<FinesState> emit,
  ) async {
    try {
      await _repository.updateFineAmount(event.fineId, event.newAmount);
      add(LoadFines());
    } catch (e) {
      emit(
        FinesError(
          toUserFriendlyErrorMessage(e, fallback: 'Failed to update fine amount.'),
          fines: state.fines,
          allFines: state.allFines,
        ),
      );
    }
  }

  Future<void> _onManualAssignFine(
    ManualAssignFine event,
    Emitter<FinesState> emit,
  ) async {
    emit(state.copyWith(isProcessing: true));
    try {
      await _repository.assignFine(event.fineId, event.riderId);
      add(LoadFines());
    } catch (e) {
      emit(
        FinesError(
          toUserFriendlyErrorMessage(e, fallback: 'Failed to assign fine.'),
          fines: state.fines,
          allFines: state.allFines,
        ),
      );
    } finally {
      emit(state.copyWith(isProcessing: false));
    }
  }

  Future<void> _onPaySelectedFines(
    PaySelectedFines event,
    Emitter<FinesState> emit,
  ) async {
    emit(state.copyWith(isProcessing: true));
    try {
      await _repository.payFinesToGovernment(event.fineIds, event.drawerId);
      add(LoadFines());
      if (event.fineIds.length == state.selectedIds.length) {
         emit(state.copyWith(selectedIds: {})); 
      }
    } catch (e) {
      emit(
        FinesError(
          toUserFriendlyErrorMessage(e, fallback: 'Failed to pay selected fines.'),
          fines: state.fines,
          allFines: state.allFines,
        ),
      );
    } finally {
      emit(state.copyWith(isProcessing: false));
    }
  }

  Future<void> _onBulkUpdateFineStatus(
    BulkUpdateFineStatus event,
    Emitter<FinesState> emit,
  ) async {
    emit(state.copyWith(isProcessing: true));
    try {
      await _repository.bulkUpdateStatus(event.fineIds, event.status);
      add(LoadFines());
    } catch (e) {
      emit(
        FinesError(
          toUserFriendlyErrorMessage(e, fallback: 'Failed to update selected fines.'),
          fines: state.fines,
          allFines: state.allFines,
        ),
      );
    } finally {
      emit(state.copyWith(isProcessing: false, selectedIds: {}));
    }
  }

  Future<void> _onFetchAssignmentProof(
    FetchAssignmentProof event,
    Emitter<FinesState> emit,
  ) async {
    emit(state.copyWith(isProofLoading: true, clearProof: true));
    try {
      final proof = await _repository.fetchAssignmentProof(event.fineId);
      emit(state.copyWith(assignmentProof: proof, isProofLoading: false));
    } catch (e) {
      emit(state.copyWith(isProofLoading: false));
    }
  }

  void _onToggleFineSelection(
    ToggleFineSelection event,
    Emitter<FinesState> emit,
  ) {
    final newSelected = Set<String>.from(state.selectedIds);
    if (newSelected.contains(event.fineId)) {
      newSelected.remove(event.fineId);
    } else {
      newSelected.add(event.fineId);
    }
    emit(state.copyWith(selectedIds: newSelected));
  }

  void _onClearSelection(ClearSelection event, Emitter<FinesState> emit) {
    emit(state.copyWith(selectedIds: {}));
  }

  void _onSearchFines(SearchFines event, Emitter<FinesState> emit) {
    final newState = state.copyWith(searchQuery: event.query);
    _applyFilters(emit, newState);
  }

  void _onFilterFines(FilterFines event, Emitter<FinesState> emit) {
    final newState = state.copyWith(
      filterStatus: event.status,
      filterMonth: event.month,
      filterHighAmount: event.highAmount,
      clearStatus: event.clearStatus,
      clearMonth: event.clearMonth,
      clearAmount: event.clearAmount,
    );
    _applyFilters(emit, newState);
  }

  Future<void> _onAutoMatchFines(
    AutoMatchFines event,
    Emitter<FinesState> emit,
  ) async {
    emit(state.copyWith(isProcessing: true));
    try {
      final assignments = state.assignments;
      int matchCount = 0;

      for (var fineId in event.fineIds) {
        final fine = state.allFines.firstWhere((f) => f.id == fineId);
        final violationDate = fine.violationDate;
        
        // Normalize plate for comparison
        final normPlate = fine.plateNumber.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

        // Find assignments for this bike
        final bikeAssignments = assignments.where((a) {
          final aPlate = a.plateNumber?.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '') ?? '';
          final aChassis = a.chassisNumber.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
          return aPlate == normPlate || aChassis == normPlate;
        }).toList();

        List<String> matchedRiderIds = [];
        for (var assignment in bikeAssignments) {
          bool started = assignment.assignedAt.isBefore(violationDate) ||
                         assignment.assignedAt.isAtSameMomentAs(violationDate);
          bool ended = assignment.returnedAt != null &&
                       assignment.returnedAt!.isBefore(violationDate);
          
          if (started && !ended) {
            matchedRiderIds.add(assignment.riderId);
          }
        }

        // Strictly match ONLY if exactly one assignment found
        if (matchedRiderIds.length == 1) {
          await _repository.assignFine(fine.id, matchedRiderIds.first);
          matchCount++;
        }
      }
      print("Completed auto-match. Matches found: $matchCount");
    } catch (e) {
      print("Error in _onAutoMatchFines: $e");
    } finally {
      // ALWAYS reload from DB
      add(LoadFines());
      emit(state.copyWith(isProcessing: false));
    }
  }

  Future<void> _onConfirmPartialMatch(
    ConfirmPartialMatch event,
    Emitter<FinesState> emit,
  ) async {
    emit(state.copyWith(isProcessing: true));
    try {
      final fine = state.allFines.firstWhere((f) => f.id == event.fineId);
      if (fine.riderId != null) {
        await _repository.assignFine(fine.id, fine.riderId!);
      }
    } catch (e) {
      print("Error in _onConfirmPartialMatch: $e");
    } finally {
      add(LoadFines());
      emit(state.copyWith(isProcessing: false));
    }
  }

  Future<void> _onUnlinkRider(
    UnlinkRider event,
    Emitter<FinesState> emit,
  ) async {
    emit(state.copyWith(isProcessing: true));
    try {
      await _repository.unlinkFine(event.fineId);
    } catch (e) {
      print("Error in _onUnlinkRider: $e");
    } finally {
      add(LoadFines());
      emit(state.copyWith(isProcessing: false));
    }
  }
}
