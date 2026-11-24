"""Quote MCP: business outcomes and internal spans, independent of Policy."""
import os

import boto3
from mcp.server.fastmcp import FastMCP
from mcp.server.transport_security import TransportSecuritySettings
from opentelemetry import trace

tracer = trace.get_tracer('quote.sample')
mcp = FastMCP('Quote observability', host='0.0.0.0', port=8000,
              stateless_http=True, json_response=True,
              transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False))


def quote(product_id, quantity, database, table):
    with tracer.start_as_current_span('quote.calculate_quote') as operation:
        operation.set_attributes({'quote.product_id': product_id, 'quote.quantity': quantity})
        # botocore instrumentation creates the DynamoDB.GetItem child span.
        response = database.get_item(TableName=table, Key={'product_id': {'S': product_id}},
                                     ConsistentRead=True)
        item = response.get('Item')
        with tracer.start_as_current_span('quote.check_product') as check:
            outcome = 'FOUND' if item else 'NOT_FOUND'
            check.set_attribute('quote.lookup_outcome', outcome)
        if not item:
            operation.set_attribute('quote.outcome', 'NOT_FOUND')
            return {'status': 'NOT_FOUND', 'product_id': product_id,
                    'message': '商品が見つかりません'}
        with tracer.start_as_current_span('quote.compute_total') as compute:
            unit_price = int(item['unit_price']['N'])
            total = unit_price * quantity
            compute.set_attribute('quote.total', total)
        operation.set_attribute('quote.outcome', 'SUCCESS')
        return {'status': 'SUCCESS', 'product_id': product_id, 'name': item['name']['S'],
                'unit_price': unit_price, 'quantity': quantity, 'total': total, 'currency': 'JPY'}


@mcp.tool()
def calculate_quote(product_id: str, quantity: int) -> dict:
    """Look up a product and quote its total price. Missing products return NOT_FOUND."""
    if quantity < 1:
        raise ValueError('quantity must be positive')
    return quote(product_id, quantity, boto3.client('dynamodb'), os.environ['PRODUCT_TABLE'])


def main():
    import uvicorn
    from opentelemetry.instrumentation.asgi import OpenTelemetryMiddleware
    app = OpenTelemetryMiddleware(mcp.streamable_http_app(), exclude_spans=['receive', 'send'])
    uvicorn.run(app, host='0.0.0.0', port=8000)


if __name__ == '__main__':
    main()
