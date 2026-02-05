version 1.0

workflow Microreact_Add_Teammates {
	input {
		File token
		String team_uri
		Array[String] teammate_emails
		Boolean verbose        = true
		Int max_python_retries = 1
		Int max_wdl_retries    = 0
	}

	call mr_add_teammate {
		input:
			token = token,
			team_uri = team_uri,
			teammate_emails = teammate_emails,
			verbose = verbose,
			max_python_retries = max_python_retries,
			max_wdl_retries = max_wdl_retries
	}

}

task mr_add_teammate {
	input {
		File token
		String team_uri
		Array[String] teammate_emails
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

		# this seems to be the most consistent way of doing this
		emails = "~{sep=',' teammate_emails}".split(",")
		payload_dict = {
			"team": "~{team_uri}",
			"emails": emails,
		}
		payload = json.dumps(payload_dict)
		if verbose: print(payload)
		
		def add_teammates(token, payload, retries=-1):
			if retries < ~{max_python_retries}:
				try:
					response = requests.post("https://microreact.org/api/teams/add-member",
						headers={"Access-Token": token, "Content-Type": "application/json; charset=UTF-8"},
						timeout=120,
						data=payload)
					if verbose:
						debug_print(response)
					if response.status_code == 200:
						users = response.json()
						return users
					print(f"Failed to add members to team ~{team_uri} [code {response.status_code}]: {response.text}")
					retries =+ 1
					wait(retries)
					add_teammates(token, payload, retries)
				except Exception as e: # ignore: broad-exception-caught
					print(f"Caught exception trying to list members of team ~{team_uri}: {e}")
					retries =+ 1
					wait(retries)
					add_teammates(token, payload, retries)
			else:
				print(f"Failed to add members to team ~{team_uri} after ~{max_python_retries} attempt(s). Something's broken.")
				exit(1)

		add_teammates(TOKEN_STR, payload)

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

}
