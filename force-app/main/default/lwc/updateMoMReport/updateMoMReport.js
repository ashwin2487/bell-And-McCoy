import { LightningElement,api } from 'lwc';
import runBatch from '@salesforce/apex/UpdateMoMReportController.runBatch';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
export default class UpdateMoMReport extends LightningElement {
        @api recordId;
    
        handleRunBatch() {
            runBatch({ momReportId: this.recordId})
                .then(() => {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Success',
                            message: 'Batch started successfully!',
                            variant: 'success'
                        })
                    );
                })
                .catch(error => {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Error',
                            message: error.body?.message || error.message,
                            variant: 'error'
                        })
                    );
                });
        }
}