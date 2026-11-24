"""Persistent ownership and immutable handoff receipts, separate from model output."""
from botocore.exceptions import ClientError
from contracts import digest, encoded
import json


def conditional(exc):
    return isinstance(exc, ClientError) and exc.response['Error']['Code'] == 'ConditionalCheckFailedException'


class Store:
    def __init__(self, resource, state, private=None, inbox=None):
        self.resource = resource
        self.state = resource.Table(state)
        self.private = resource.Table(private) if private else None
        self.inbox = resource.Table(inbox) if inbox else None

    def get_state(self, cid):
        item = self.state.get_item(Key={'case_id': cid}, ConsistentRead=True).get('Item')
        if not item: raise ValueError('Case not found')
        item['version'] = int(item['version'])
        if 'progress_json' in item:
            item['progress'] = json.loads(item.pop('progress_json'))
        return item

    def create(self, cid, mode, notes):
        fingerprint = digest({'mode': mode, 'notes': notes})
        items = [(self.state.name, {'case_id': cid, 'owner': 'predecessor', 'version': 0, 'mode': mode, 'source_hash': fingerprint}),
                 (self.private.name, {'case_id': cid, 'notes': notes})]
        try:
            self.resource.meta.client.transact_write_items(TransactItems=[{'Put': {
                'TableName': table, 'Item': item,
                'ConditionExpression': 'attribute_not_exists(case_id)'}} for table, item in items])
        except ClientError as exc:
            if exc.response['Error']['Code'] != 'TransactionCanceledException': raise
            existing = self.get_state(cid)
            if existing.get('source_hash') != fingerprint: raise ValueError('Case ID already used with different input') from exc
        return self.get_state(cid)

    def notes(self, cid):
        item = self.private.get_item(Key={'case_id': cid}, ConsistentRead=True).get('Item')
        if not item: raise ValueError('Private notes missing')
        return item['notes']

    def receive(self, cid, packet, tid):
        item = {'case_id': cid, 'packet': packet, 'transfer_id': tid}
        try:
            self.inbox.put_item(Item=item, ConditionExpression='attribute_not_exists(case_id)')
        except ClientError as exc:
            if not conditional(exc): raise
            if self.receipt(cid) != item: raise ValueError('Conflicting handoff receipt') from exc
        return item

    def receipt(self, cid):
        item = self.inbox.get_item(Key={'case_id': cid}, ConsistentRead=True).get('Item')
        if not item: raise ValueError('Handoff receipt missing')
        return item

    def save_progress(self, cid, expected, progress):
        values = {':prev': 'predecessor', ':new': encoded(progress).decode()}
        condition = '#o = :prev AND attribute_not_exists(progress_json)'
        if expected is not None:
            condition = '#o = :prev AND progress_json = :expected'
            values[':expected'] = encoded(expected).decode()
        self.state.update_item(Key={'case_id': cid}, UpdateExpression='SET progress_json = :new',
            ConditionExpression=condition, ExpressionAttributeNames={'#o': 'owner'},
            ExpressionAttributeValues=values)

    def cached_review(self, cid, revision):
        item = self.inbox.get_item(Key={'case_id': f'{cid}/review/{revision}'}, ConsistentRead=True).get('Item')
        return json.loads(item['record_json']) if item else None

    def save_review(self, cid, revision, record):
        try:
            self.inbox.put_item(Item={'case_id': f'{cid}/review/{revision}', 'record_json': encoded(record).decode()},
                                ConditionExpression='attribute_not_exists(case_id)')
        except ClientError as exc:
            if not conditional(exc): raise
            existing = self.cached_review(cid, revision)
            if existing['input_hash'] != record['input_hash']: raise ValueError('Conflicting review input') from exc
            return existing
        return record

    def commit(self, cid, tid, progress=None):
        values = {':next': 'successor', ':prev': 'predecessor', ':one': 1, ':zero': 0, ':tid': tid}
        update = 'SET #o = :next, #v = :one, transfer_id = :tid'
        condition = '#o = :prev AND #v = :zero'
        if progress is not None:
            values[':expected'] = encoded(progress).decode()
            values[':completed'] = encoded({**progress, 'phase': 'completed'}).decode()
            update += ', progress_json = :completed'
            condition += ' AND progress_json = :expected'
        try:
            self.state.update_item(Key={'case_id': cid},
                UpdateExpression=update,
                ConditionExpression=condition,
                ExpressionAttributeNames={'#o': 'owner', '#v': 'version'},
                ExpressionAttributeValues=values)
        except ClientError as exc:
            if not conditional(exc): raise
            current = self.get_state(cid)
            if current['owner'] != 'successor' or current.get('transfer_id') != tid:
                raise ValueError('Conflicting owner transition') from exc
        return self.get_state(cid)
