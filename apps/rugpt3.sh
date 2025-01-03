#!/bin/bash
docker run -it dimedrol/rugpt3:1a83ef8 python /rugpt/generate_transformers.py --model_type=gpt2 --model_name_or_path=sberbank-ai/rugpt3large_based_on_gpt2 --k=5 --p=0.95 --length=100 --prompt="Открытое ПО творит чудеса"
