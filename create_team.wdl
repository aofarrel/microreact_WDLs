version 1.0

workflow Microreact_Create_Team {
	input {
		File token
		String team_name
	}

	call mr_new_team {
		input:
			token = token,
			team_name = team_name
	}

	output {
		String new_team_uri = mr_new_team.new_team_uri
	}
}

task mr_new_team {
	input {
		File token
		String team_name
	}
	
	command <<<
		set -eu pipefail
		set +x
		python3 << CODE
		import requests
		import time
		import json

		with open("~{token}", 'r', encoding="utf-8") as file:
			TOKEN_STR = file.readline().strip()

		def create_new_mr_team(token, retries=-1): # returns new URL
			retries += 1
			json = '{\n  "name": "~{team_name}"\n}'
			if retries < 3:
				try:
					response = requests.post("https://microreact.org/api/teams/create",
						headers={"Access-Token": token, "Content-Type": "application/json; charset=UTF-8"},
						timeout=120,
						data=json)
					if response.status_code == 200:
						URL = response.json()['id']
						return URL
					print(f"Failed to create new MR team [code {response.status_code}]: {response.text}")
					print("WAITING TWO SECONDS, THEN RETRYING...")
					time.sleep(2)
					create_new_mr_team(token, retries)
				except Exception as e: # ignore: broad-exception-caught
					print(f"Caught exception trying to create new MR team: {e}")
					if retries != 2:
						print("WAITING TWO SECONDS, THEN RETRYING...")
						time.sleep(2)
					else:
						print("WAITING ONE MINUTE, THEN RETRYING...")
						time.sleep(60)
					create_new_mr_team(token, retries)
			else:
				print(f"Failed to create new MR team after multiple retries. Something's broken.")
				exit(1)
			return None

		uri = create_new_mr_team(TOKEN_STR)

		with open("uri.txt", "w", encoding="utf-8") as outfile:
			outfile.write(uri)

		CODE

	>>>

	runtime {
		cpu: 2
		disks: "local-disk 10 HDD"
		docker: "ashedpotatoes/dropkick:0.0.2"
		memory: "8 GB"
		preemptible: 2
		maxRetries: 1
	}

	output {
		String new_team_uri = read_string("uri.txt")
	}
}
