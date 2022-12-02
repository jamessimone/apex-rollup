String SCRIPT_VAR_1 = 'INSERT_UTC_TIME_IN_SECONDS_HERE';
Datetime jobFilter = Datetime.newInstance(Long.valueOf(SCRIPT_VAR_1) * 1000);
System.debug('Starting up with job filter time of: ' + Datetime.newInstanceGmt(jobFilter.date(), jobFilter.time()));

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
  if (updatedAccount.AnnualRevenue != 3199960013L) {
    throw new MathException('Should have been properly summed by Apex Rollup!');
  } else {
    returnMessage = 'COMPLETED';
  }
}
System.debug(returnMessage);
