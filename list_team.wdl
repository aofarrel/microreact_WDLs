version 1.0

workflow Microreact_List_Team {
	input {
		File token
		String team_uri
		Boolean verbose = false
	}

	call mr_new_team {
		input:
			token = token,
			team_uri = team_uri,
			verbose = verbose
	}

	output {
		String new_team_uri = mr_new_team.new_team_uri
	}
}

task mr_new_team {
	input {
		File token
		String team_uri
		Boolean verbose
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

		payload = '{\n  "team": "~{team_uri}"\n}'

		def debug_print(response):
			print(f"[DEBUG] Status code: {response.status_code}")
			print(f"[DEBUG] Response body: {response.text!r}")
			print(f"[DEBUG] Response headers: {dict(response.headers)}")
			return

		def list_mr_team_members(token, payload, retries=-1): # returns new URL
			retries += 1
			if retries < 3:
				try:
					response = requests.post("https://microreact.org/api/teams/list-members",
						headers={"Access-Token": token, "Content-Type": "application/json; charset=UTF-8"},
						timeout=120,
						data=payload)
					if verbose:
						debug_print(response)
					if response.status_code == 200:
						users = response.json()
						print(users)
						return users
					print(f"Failed to list members of ~{team_uri} [code {response.status_code}]: {response.text}")
					print("WAITING TWO SECONDS, THEN RETRYING...")
					time.sleep(2)
					list_mr_team_members(token, payload, retries)
				except Exception as e: # ignore: broad-exception-caught
					print(f"Caught exception trying to list members of team ~{team_uri}: {e}")
					if retries != 2:
						print("WAITING TWO SECONDS, THEN RETRYING...")
						time.sleep(2)
					else:
						print("WAITING ONE MINUTE, THEN RETRYING...")
						time.sleep(60)
					list_mr_team_members(token, payload, retries)
			else:
				print(f"Failed to list members of team ~{team_uri} after multiple retries. Something's broken.")
				exit(1)
			return None

		members = list_mr_team_members(TOKEN_STR, payload)

		with open("members.txt", "w", encoding="utf-8") as outfile:
			outfile.write(members)

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
		String new_team_uri = read_string("members.txt")
	}
}
