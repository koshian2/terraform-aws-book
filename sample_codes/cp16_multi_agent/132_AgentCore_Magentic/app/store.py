import json
from botocore.exceptions import ClientError
from contracts import encoded


class Store:
    def __init__(self, table): self.table = table

    def get(self, cid):
        item = self.table.get_item(Key={'case_id': cid}, ConsistentRead=True).get('Item')
        if not item: raise ValueError('Case not found')
        return json.loads(item['document'])

    def create(self, state):
        try:
            self.table.put_item(Item={'case_id': state['case_id'], 'document': encoded(state).decode()},
                                ConditionExpression='attribute_not_exists(case_id)')
        except ClientError as exc:
            if exc.response['Error']['Code'] != 'ConditionalCheckFailedException': raise
            existing = self.get(state['case_id'])
            if existing['scenario'] != state['scenario'] or existing['request'] != state['request']:
                raise ValueError('Case ID already used with different input') from exc
        return self.get(state['case_id'])

    def save(self, previous, state):
        self.table.update_item(Key={'case_id': state['case_id']},
            UpdateExpression='SET document = :new', ConditionExpression='document = :old',
            ExpressionAttributeValues={':new': encoded(state).decode(), ':old': encoded(previous).decode()})
