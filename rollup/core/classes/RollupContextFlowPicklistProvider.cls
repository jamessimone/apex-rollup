public class RollupContextFlowPicklistProvider extends VisualEditor.DynamicPicklist {
  @SuppressWarnings('PMD.FieldNamingConventions')
  private static final List<String> RESERVED_CONTEXT_KEYWORDS = new List<String>{ 'INSERT', 'UPDATE', 'UPSERT', 'DELETE', 'REFRESH' };

  public override VisualEditor.DataRow getDefaultValue() {
    return new VisualEditor.DataRow(RESERVED_CONTEXT_KEYWORDS[0], RESERVED_CONTEXT_KEYWORDS[0]);
  }

  public override VisualEditor.DynamicPickListRows getValues() {
    VisualEditor.DynamicPickListRows values = new VisualEditor.DynamicPickListRows();
    for (String context : RESERVED_CONTEXT_KEYWORDS) {
      values.addRow(new VisualEditor.DataRow(context, context));
    }
    return values;
  }
}
