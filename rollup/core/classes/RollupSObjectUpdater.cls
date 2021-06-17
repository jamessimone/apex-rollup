public class RollupSObjectUpdater {
  private final Schema.SObjectField fieldToken;

  public RollupSObjectUpdater(Schema.SObjectField fieldToken) {
    this.fieldToken = fieldToken;
  }

  public void updateField(SObject record, Object value) {
    try {
      record.put(this.fieldToken, value);
    } catch (SObjectException sObjException) {
      this.handleUpdateException(sObjException, record, value);
    }
  }

  private void handleUpdateException(SObjectException ex, SObject record, Object value) {
    switch on ex.getMessage() {
      when 'Illegal assignment from Datetime to Date' {
        Datetime dtValue = (Datetime) value;
        record.put(this.fieldToken, dtValue.dateGmt());
      }
      when else {
        // so far Datetime -> Date has been the only reported issue
        // this switch statement can be expanded as necessary to deal with other problems
        throw ex;
      }
    }
  }
}
