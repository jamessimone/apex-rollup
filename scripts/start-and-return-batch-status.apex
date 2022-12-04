String SCRIPT_VAR_1 = 'INSERT_UTC_TIME_IN_SECONDS_HERE';
String SCRIPT_VAR_2 = '0';
Datetime jobFilter = Datetime.newInstance(Long.valueOf(SCRIPT_VAR_1) * 1000);
System.debug('Starting up with job filter time of: ' + Datetime.newInstanceGmt(jobFilter.date(), jobFilter.time()));

if (RollupSettings__c.getOrgDefaults()?.IsEnabled__c != true) {
  upsert new RollupSettings__c(IsEnabled__c = true);
}

List<AsyncApexJob> potentiallyMatchingJobs = [
  SELECT Status
  FROM AsyncApexJob
  WHERE ApexClass.Name = :RollupFullBatchRecalculator.class.getName() AND CreatedDate >= :jobFilter AND ParentJobId = NULL
  ORDER BY CreatedDate DESC
  LIMIT 1
];

System.debug(potentiallyMatchingJobs);

String returnMessage = 'PENDING';
if (potentiallyMatchingJobs.isEmpty()) {
  Rollup.performBulkFullRecalc(
    new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Opportunity',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnCalcItem__c = 'Amount',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM'
      )
    },
    Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name()
  );
} else if (potentiallyMatchingJobs.get(0).Status == 'Completed') {
  Account updatedAccount = [SELECT AnnualRevenue FROM Account WHERE Name = 'sForce'];
  System.debug('Updated account value: ' + JSON.serialize(updatedAccount));
  if (updatedAccount.AnnualRevenue != Long.valueOf(SCRIPT_VAR_2)) {
    throw new MathException('Should have been properly summed by Apex Rollup! Got ' + updatedAccount.AnnualRevenue + ' instead');
  } else {
    returnMessage = 'COMPLETED';
  }
}
System.debug(returnMessage);
