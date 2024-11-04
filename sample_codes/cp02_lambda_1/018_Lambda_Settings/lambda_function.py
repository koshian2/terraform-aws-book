import math
import time
import json

def is_prime(n):
    """与えられた数が素数かどうかを判定する関数"""
    if n < 2:
        return False
    for i in range(2, int(math.isqrt(n)) + 1):
        if n % i == 0:
            return False
    return True

def find_primes(limit):
    """指定された範囲内の素数をリストで返す関数"""
    primes = []
    for num in range(2, limit + 1):
        if is_prime(num):
            primes.append(num)
    return primes

def lambda_handler(event, context):
    limit = event.get("limit", 100000)  # 処理する上限値
    start_time = time.time()
    
    primes = find_primes(limit)
    
    end_time = time.time()
    response = {
        "limit": limit, 
        "num_primes": len(primes),
        "elapsed": end_time - start_time
    }

    return {
        'statusCode': 200,
        'body': json.dumps(response)
    }
