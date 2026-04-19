import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/journal_template_model.dart';
import 'journal_template_repository.dart';

class SupabaseJournalTemplateRepository implements JournalTemplateRepository {
  final SupabaseClient _client = Supabase.instance.client;

  @override
  Future<List<JournalTemplateModel>> fetchTemplates() async {
    try {
      final response = await _client
          .from('journal_templates')
          .select()
          .order('name');
      
      return (response as List)
          .map((json) => JournalTemplateModel.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching journal templates: $e');
      rethrow;
    }
  }

  @override
  Future<void> createTemplate(JournalTemplateModel template) async {
    try {
      await _client.from('journal_templates').insert(template.toJson());
    } catch (e) {
      print('Error creating journal template: $e');
      rethrow;
    }
  }

  @override
  Future<void> deleteTemplate(String id) async {
    try {
      await _client.from('journal_templates').delete().eq('id', id);
    } catch (e) {
      print('Error deleting journal template: $e');
      rethrow;
    }
  }
}
