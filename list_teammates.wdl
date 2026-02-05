version 1.0

workflow Microreact_List_Team {
	input {
		File token
		String team_uri
		Boolean verbose        = true
		Int max_python_retries = 1
		Int max_wdl_retries    = 0
	}

	call mr_list_team_members {
		input:
			token = token,
			team_uri = team_uri,
			verbose = verbose,
			max_python_retries = max_python_retries,
			max_wdl_retries = max_wdl_retries
	}

	output {
		Array[String] emails = mr_list_team_members.emails
		File emails_roles_datestamp = mr_list_team_members.emails_roles_datestamp
	}
}

task mr_list_team_members {
	input {
		File token
		String team_uri
		Boolean verbose
		Int max_python_retries
		Int max_wdl_retries
	}
	
	command <<<
		set -eu pipefail
		set +x
		python3 << CODE
		import requests
		import time
		import json

		# https://github.com/openwdl/wdl/blob/legacy/versions/1.0/SPEC.md#true-and-false
		verbose = bool(~{true='True' false='False' verbose})
		assert type(verbose) == bool

		with open("~{token}", 'r', encoding="utf-8") as file:
			TOKEN_STR = file.readline().strip()

		def debug_print(response):
			print(f"[DEBUG] Status code: {response.status_code}")
			print(f"[DEBUG] Response body: {response.text!r}")
			print(f"[DEBUG] Response headers: {dict(response.headers)}")
			return

		def wait(retries):
			if ~{max_python_retries} - retries == 1:
				print("WAITING ONE MINUTE, THEN RETRYING...")
				time.sleep(60)
			elif ~{max_python_retries} - retries <= 0:
				return
			else:
				print("WAITING TWO SECONDS, THEN RETRYING...")
				time.sleep(2)

		payload = '{\n  "team": "~{team_uri}"\n}'
		
		def list_mr_team_members(token, payload, retries=-1):
			if retries < ~{max_python_retries}:
				try:
					response = requests.post("https://microreact.org/api/teams/list-members",
						headers={"Access-Token": token, "Content-Type": "application/json; charset=UTF-8"},
						timeout=120,
						data=payload)
					if verbose:
						debug_print(response)
					if response.status_code == 200:
						users = response.json()
						return users
					print(f"Failed to list members of ~{team_uri} [code {response.status_code}]: {response.text}")
					retries =+ 1
					wait(retries)
					list_mr_team_members(token, payload, retries)
				except Exception as e: # ignore: broad-exception-caught
					print(f"Caught exception trying to list members of team ~{team_uri}: {e}")
					retries =+ 1
					wait(retries)
					list_mr_team_members(token, payload, retries)
			else:
				print(f"Failed to list members of team ~{team_uri} after ~{max_python_retries} retries. Something's broken.")
				exit(1)

		# response is a list of dictionaries, ex: '[{"email":"foo@bar.edu","role":"viewer","added":"2026-02-03T23:01:51.691Z"}]'
		# list-of-dict isn't valid for writelines() so we'll use JSON
		full_output = list_mr_team_members(TOKEN_STR, payload)
		with open("teammates_full_details.json", "w", encoding="utf-8") as outfile:
			json.dump(full_output, outfile)

		emails = []
		for teammate in full_output:
			emails.append(teammate['email'])

		with open("emails.txt", "w", encoding="utf-8") as outfile:
			outfile.writelines(emails)

		CODE

	>>>

	runtime {
		cpu: 2
		disks: "local-disk 10 HDD"
		docker: "ashedpotatoes/dropkick:0.0.2"
		memory: "8 GB"
		preemptible: 2
		maxRetries: max_wdl_retries
	}

	output {
		Array[String] emails = read_lines("emails.txt")
		File emails_roles_datestamp = "teammates_full_details.json"
	}
}
