import { LightningElement, api } from 'lwc';
import runBatch from '@salesforce/apex/DealerImportBatchService.runBatch';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class DealerImportDataProcess extends LightningElement {
    @api recordId;

    handleRunBatch() {
        runBatch({ importRecordId: this.recordId})
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