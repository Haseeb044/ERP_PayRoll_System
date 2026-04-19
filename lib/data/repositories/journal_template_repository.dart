import '../models/journal_template_model.dart';

abstract class JournalTemplateRepository {
  Future<List<JournalTemplateModel>> fetchTemplates();
  Future<void> createTemplate(JournalTemplateModel template);
  Future<void> deleteTemplate(String id);
}
