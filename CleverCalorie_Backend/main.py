#!flask/bin/python
from flask import Flask, jsonify
import json, requests

app = Flask(__name__)

base_url = 'https://api.nutritionix.com/v1_1/search/'
param = '?fields=item_name%2Citem_id%2Cbrand_name%2Cnf_calories%2Cnf_calories_from_fat%2Cnf_total_fat&appId=af0e6ef8&appKey=cc7d3058decebf79bc75d1bc537f1eab'

@app.route('/search/<query>', methods=['GET'])
def get_tasks(query):
    str = query.split(",")
    print len(str)
    return_data = []
    for item in str:
        url = base_url + item + param
        r = requests.get(url)
        data = json.loads(r.text)
        result = {}
        result['name'] = item
        result['calories'] = data['hits'][0]['fields']['nf_calories']
        result['total_fat'] = data['hits'][0]['fields']['nf_total_fat']
        result['calories_fat'] = data['hits'][0]['fields']['nf_calories_from_fat']
        return_data.append(result)
    return jsonify(return_data)

@app.route('/', methods=['GET'])
def test_route():
    return 'Reached working server'
if __name__ == '__main__':
    app.run(debug=True)