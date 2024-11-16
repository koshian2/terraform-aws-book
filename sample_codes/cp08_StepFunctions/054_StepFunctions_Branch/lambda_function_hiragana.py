import random

def lambda_handler(event, context):
    hiragana_list = [chr(i) for i in range(0x3042, 0x3094)] # あ～ん
    num_selected = random.randint(1, 5)
    selected_hiragana = random.sample(hiragana_list, num_selected)

    return {
        'statusCode': 200,
        'hiragana': selected_hiragana
    }
