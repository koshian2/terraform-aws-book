import random

def lambda_handler(event, context):
    katakana_list = [chr(i) for i in range(0x30A2, 0x30F4)] # ア～ン
    num_selected = random.randint(1, 5)
    selected_katakana = random.sample(katakana_list, num_selected)

    return {
        'statusCode': 200,
        'katakana': selected_katakana
    }
