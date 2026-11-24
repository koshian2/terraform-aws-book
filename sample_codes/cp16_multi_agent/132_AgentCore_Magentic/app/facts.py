"""Fictional source facts and deterministic arithmetic, not model-generated data."""
def lookup(role, source, scenario, params):
    if role == 'repair': return dict(source[scenario][params['stage']])
    days = params['days']
    if role == 'insurance':
        covered = min(days, source['covered_days_max'])
        return {**source, 'requested_days': days, 'covered_days': covered, 'uncovered_days': days-covered}
    vehicle = source[params['vehicle']]
    return {**vehicle, 'vehicle': params['vehicle'], 'requested_days': days,
            'available': days <= vehicle['available_days_max'], 'total_yen': days*vehicle['daily_yen'],
            'pricing_assumptions': '架空の税込日額×日数。免責・燃料・追加料金は本例では扱いません。'}
