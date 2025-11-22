def lambda_handler(event, context):
    record = event['Records'][0]['cf']
    request = record['request']
    response = record['response']

    status_str = response.get('status', '0')
    try:
        status = int(status_str)
    except ValueError:
        return response

    target_status_codes = {403, 404, 500, 503}

    if status in target_status_codes:
        uri = request.get('uri', '')

        # 無限ループ防止：すでに /error.html にいる場合は何もしない
        if uri.startswith('/error.html'):
            return response

        error_type = str(status)

        # シンプルに type だけ付ける
        location = f"/error.html?type={error_type}"

        new_response = {
            'status': '302',
            'statusDescription': 'Found',
            'headers': {
                'location': [
                    {
                        'key': 'Location',
                        'value': location,
                    }
                ],
                'cache-control': [
                    {
                        'key': 'Cache-Control',
                        'value': 'no-cache',
                    }
                ],
                'content-type': [
                    {
                        'key': 'Content-Type',
                        'value': 'text/html',
                    }
                ],
            },
        }
        return new_response

    return response
